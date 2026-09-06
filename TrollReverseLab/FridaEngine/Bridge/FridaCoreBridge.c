//
//  FridaCoreBridge.c
//  TrollReverseLab
//
//  Real frida-core embedding (devkit 17.17.0, ios-arm64).
//
//  线程模型（v6.4.1 修正——TRL 四连崩验尸结论）：
//  - GLib 首次初始化（frida_init / g_main_loop_new / device manager）
//    只允许发生在本桥的专用线程内，任何调用方线程提前触碰 GLib
//    都会和 frida_init 撞出 thread-state 竞态（SEGV @0x8，栈：
//    g_main_loop_new → g_once_init_enter → g_thread_state_add）。
//  - fcb_init 只做两件事：起专用线程 + 等状态机就绪。
//  - attach/load/unload/detach 的阻塞调用经 g_call_lock 串行化，
//    防收件箱脚本与用户手动执行并发捅 session。
//

#include "FridaCoreBridge.h"
#include "frida-core.h"

#include <pthread.h>
#include <string.h>
#include <stdio.h>

static FridaDeviceManager *g_manager = NULL;
static FridaDevice *g_local_device = NULL;
static GMainLoop *g_loop = NULL;
static FridaSession *g_session = NULL;
static FridaScript *g_script = NULL;

static fcb_message_fn g_msg_cb = NULL;
static void *g_msg_ctx = NULL;
static fcb_state_fn g_state_cb = NULL;
static void *g_state_ctx = NULL;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static char g_last_error[512] = {0};

// init 状态机：fcb_init 只起线程，绝不亲手碰 GLib
typedef enum {
  FCB_STATE_IDLE = 0,
  FCB_STATE_STARTING = 1,
  FCB_STATE_READY = 2,
  FCB_STATE_FAILED = 3
} FcbState;
static FcbState g_state = FCB_STATE_IDLE;

// 串行化阻塞型 frida 调用（attach/load/unload/detach 全程持锁）
static pthread_mutex_t g_call_lock = PTHREAD_MUTEX_INITIALIZER;

static void set_last_error(const char *msg)
{
  if (msg == NULL) msg = "unknown error";
  pthread_mutex_lock(&g_lock);
  snprintf(g_last_error, sizeof (g_last_error), "%s", msg);
  pthread_mutex_unlock(&g_lock);
}

static int copy_err(char *err, int err_len, const char *msg);

static void note_failed(const char *msg)
{
  copy_err(NULL, 0, msg);
  pthread_mutex_lock(&g_lock);
  g_state = FCB_STATE_FAILED;
  pthread_mutex_unlock(&g_lock);
}

static int copy_err(char *err, int err_len, const char *msg)
{
  set_last_error(msg);
  if (err != NULL && err_len > 0)
    snprintf(err, err_len, "%s", msg);
  return -1;
}

static int copy_gerror(char *err, int err_len, GError **errorp)
{
  if (errorp != NULL && *errorp != NULL)
  {
    // strdup BEFORE free —— 直接引用 (*errorp)->message 拷贝是 use-after-free
    // （v6.4.1 实锤：attach 失败信息变乱码 `@˖B{` 就是读的已释放内存）
    gchar *dup = g_strdup ((*errorp)->message);
    g_printerr ("[fcb] frida error: %s\n", dup != NULL ? dup : "unknown");
    g_error_free (*errorp);
    *errorp = NULL;
    int rc = copy_err (err, err_len, dup != NULL ? dup : "unknown frida error");
    g_free (dup);
    return rc;
  }
  return copy_err(err, err_len, "unknown frida error");
}

// MARK: - callbacks (GLib threads)

static void on_script_message (FridaScript * script, const gchar * message,
                               GBytes * data, gpointer user_data)
{
  fcb_message_fn cb;
  void *ctx;
  (void) script; (void) data; (void) user_data;

  pthread_mutex_lock(&g_lock);
  cb = g_msg_cb;
  ctx = g_msg_ctx;
  pthread_mutex_unlock(&g_lock);

  if (cb != NULL && message != NULL)
    cb(message, ctx);
}

typedef struct
{
  int reason;
} DetachNote;

static gboolean deliver_detach (gpointer user_data)
{
  DetachNote *note = user_data;
  fcb_state_fn cb;
  void *ctx;

  pthread_mutex_lock(&g_lock);
  // 目标进程死掉后 script/session 对象已惰性化——直接放引用，不做 sync 调用防自锁
  g_script = NULL;
  g_session = NULL;
  cb = g_state_cb;
  ctx = g_state_ctx;
  pthread_mutex_unlock(&g_lock);

  if (cb != NULL)
    cb(note->reason, ctx);
  g_free (note);
  return FALSE;
}

static void on_session_detached (FridaSession * session,
                                 FridaSessionDetachReason reason,
                                 FridaCrash * crash, gpointer user_data)
{
  DetachNote *note;
  (void) session; (void) crash; (void) user_data;

  note = g_new0 (DetachNote, 1);
  note->reason = (int) reason;
  g_idle_add (deliver_detach, note);
}

// MARK: - 专用 frida 线程（GLib 首次初始化的唯一现场）

static gpointer loop_thread_func (gpointer user_data)
{
  GError * error = NULL;
  FridaDeviceList * devices;
  gint num_devices, i;
  (void) user_data;

  // stderr → 落盘：frida-core 内部诊断（g_printerr）+ [fcb] 行全部可 SSH 旁观
  //TRL 有 no-sandbox + 绝对路径读写 entitlement，直接写全局 Documents
  {
    const char *logpath = getenv ("TRL_FRIDA_STDERR_LOG");
    if (logpath == NULL || logpath[0] == '\0')
      logpath = "/var/mobile/Documents/trl_stderr.log";
    if (freopen (logpath, "a", stderr) != NULL)
      setvbuf (stderr, NULL, _IOLBF, 0);
    g_printerr ("[fcb] === stderr capture started (frida-core %s) ===\n", frida_version_string ());
  }

  // 顺序铁律：frida_init 必须先于一切 GLib 对象创建，且全部在本线程
  frida_init ();

  g_loop = g_main_loop_new (NULL, TRUE);

  g_manager = frida_device_manager_new ();

  devices = frida_device_manager_enumerate_devices_sync (g_manager, NULL, &error);
  if (error != NULL)
  {
    copy_gerror (NULL, 0, &error);
    g_printerr ("[fcb] device enumeration failed, loop thread exiting\n");
    note_failed (fcb_last_error ());
    return NULL;
  }

  num_devices = frida_device_list_size (devices);
  for (i = 0; i != num_devices; i++)
  {
    FridaDevice * device = frida_device_list_get (devices, i);
    if (frida_device_get_dtype (device) == FRIDA_DEVICE_TYPE_LOCAL)
    {
      g_local_device = g_object_ref (device);
      g_object_unref (device);
      break;
    }
    g_object_unref (device);
  }
  frida_unref (devices);

  if (g_local_device == NULL)
  {
    copy_err (NULL, 0, "local device not found");
    g_printerr ("[fcb] no local device, loop thread exiting\n");
    note_failed ("local device not found");
    return NULL;
  }

  g_printerr ("[fcb] frida-core %s ready, local device acquired\n", frida_version_string ());

  pthread_mutex_lock(&g_lock);
  g_state = FCB_STATE_READY;
  pthread_mutex_unlock(&g_lock);

  g_main_loop_run (g_loop);   // runs forever
  return NULL;
}

// MARK: - public API

int fcb_init (char * err, int err_len)
{
  pthread_t tid;

  pthread_mutex_lock(&g_lock);
  FcbState st = g_state;
  pthread_mutex_unlock(&g_lock);

  if (st == FCB_STATE_READY)
    return 0;
  if (st == FCB_STATE_FAILED)
    return copy_err (err, err_len, fcb_last_error ());

  if (st == FCB_STATE_IDLE)
  {
    // 并发调用者只有一个能把 IDLE 推进到 STARTING 并起线程
    pthread_mutex_lock(&g_lock);
    if (g_state == FCB_STATE_IDLE)
    {
      g_state = FCB_STATE_STARTING;
      pthread_mutex_unlock(&g_lock);
      if (pthread_create (&tid, NULL, loop_thread_func, NULL) != 0)
      {
        pthread_mutex_lock(&g_lock);
        g_state = FCB_STATE_FAILED;
        pthread_mutex_unlock(&g_lock);
        return copy_err (err, err_len, "failed to spawn frida loop thread");
      }
      pthread_detach (tid);
    }
    else
    {
      pthread_mutex_unlock(&g_lock);
    }
  }

  // STARTING（含并发到达者）：等就绪/失败，frida_init 首次初始化偏重给足 10s
  for (int i = 0; i < 100; i++)
  {
    usleep (100 * 1000);
    pthread_mutex_lock(&g_lock);
    FcbState now = g_state;
    pthread_mutex_unlock(&g_lock);
    if (now == FCB_STATE_READY)
      return 0;
    if (now == FCB_STATE_FAILED)
      return copy_err (err, err_len, fcb_last_error ());
  }
  return copy_err (err, err_len, "frida-core init timeout (10s)");
}

static int fcb_attach_locked (uint32_t pid, char * err, int err_len)
{
  GError * error = NULL;
  FridaSession * session;
  FridaDevice * device;

  // 引擎层可能重复 attach（新 bridge 实例）——先清干净旧会话
  GError * stale_error = NULL;
  pthread_mutex_lock(&g_lock);
  FridaScript * stale_script = g_script;
  g_script = NULL;
  FridaSession * stale_session = g_session;
  g_session = NULL;
  pthread_mutex_unlock(&g_lock);
  if (stale_script != NULL)
  {
    frida_script_unload_sync (stale_script, NULL, NULL);
    frida_unref (stale_script);
  }
  if (stale_session != NULL)
  {
    frida_session_detach_sync (stale_session, NULL, &stale_error);
    if (stale_error != NULL) g_error_free (stale_error);
    frida_unref (stale_session);
  }

  pthread_mutex_lock(&g_lock);
  device = (g_local_device != NULL) ? g_object_ref (g_local_device) : NULL;
  pthread_mutex_unlock(&g_lock);

  if (device == NULL)
    return copy_err (err, err_len, "local device not ready");

  session = frida_device_attach_sync (device, pid, NULL, NULL, &error);
  g_object_unref (device);
  if (error != NULL)
    return copy_gerror (err, err_len, &error);

  g_signal_connect (session, "detached", G_CALLBACK (on_session_detached), NULL);

  pthread_mutex_lock(&g_lock);
  g_session = session;
  pthread_mutex_unlock(&g_lock);
  return 0;
}

int fcb_attach (uint32_t pid, char * err, int err_len)
{
  if (fcb_init (err, err_len) != 0)
    return -1;
  pthread_mutex_lock (&g_call_lock);
  int rc = fcb_attach_locked (pid, err, err_len);
  pthread_mutex_unlock (&g_call_lock);
  return rc;
}

static int fcb_load_script_locked (const char * source, char * err, int err_len)
{
  GError * error = NULL;
  FridaSession * session;
  FridaScript * script = NULL;
  FridaScriptOptions * options;

  pthread_mutex_lock(&g_lock);
  session = (g_session != NULL) ? g_object_ref (g_session) : NULL;
  pthread_mutex_unlock(&g_lock);

  if (session == NULL)
    return copy_err (err, err_len, "no attached session");

  // 先卸载旧脚本（一个会话一个活动脚本）
  pthread_mutex_lock(&g_lock);
  FridaScript * old = g_script;
  g_script = NULL;
  pthread_mutex_unlock(&g_lock);
  if (old != NULL)
  {
    frida_script_unload_sync (old, NULL, NULL);   // 失败容忍
    frida_unref (old);
  }

  options = frida_script_options_new ();
  frida_script_options_set_name (options, "trl");
  frida_script_options_set_runtime (options, FRIDA_SCRIPT_RUNTIME_QJS);

  script = frida_session_create_script_sync (session, source, options, NULL, &error);
  g_clear_object (&options);
  if (error != NULL)
  {
    g_object_unref (session);
    return copy_gerror (err, err_len, &error);
  }

  g_signal_connect (script, "message", G_CALLBACK (on_script_message), NULL);
  frida_script_load_sync (script, NULL, &error);
  if (error != NULL)
  {
    frida_unref (script);
    g_object_unref (session);
    return copy_gerror (err, err_len, &error);
  }

  pthread_mutex_lock(&g_lock);
  g_script = script;
  pthread_mutex_unlock(&g_lock);
  g_object_unref (session);
  return 0;
}

int fcb_load_script (const char * source, char * err, int err_len)
{
  pthread_mutex_lock (&g_call_lock);
  int rc = fcb_load_script_locked (source, err, err_len);
  pthread_mutex_unlock (&g_call_lock);
  return rc;
}

static int fcb_unload_script_locked (char * err, int err_len)
{
  pthread_mutex_lock(&g_lock);
  FridaScript * script = g_script;
  g_script = NULL;
  pthread_mutex_unlock(&g_lock);

  if (script == NULL)
    return 0;
  GError * error = NULL;
  frida_script_unload_sync (script, NULL, &error);
  if (error != NULL)
  {
    int rc = copy_gerror (err, err_len, &error);
    frida_unref (script);
    return rc;
  }
  frida_unref (script);
  return 0;
}

int fcb_unload_script (char * err, int err_len)
{
  pthread_mutex_lock (&g_call_lock);
  int rc = fcb_unload_script_locked (err, err_len);
  pthread_mutex_unlock (&g_call_lock);
  return rc;
}

static int fcb_detach_locked (char * err, int err_len)
{
  GError * error = NULL;
  FridaScript * script;
  FridaSession * session;

  pthread_mutex_lock(&g_lock);
  script = g_script;
  g_script = NULL;
  session = g_session;
  g_session = NULL;
  pthread_mutex_unlock(&g_lock);

  if (script != NULL)
  {
    frida_script_unload_sync (script, NULL, NULL);
    frida_unref (script);
  }
  if (session == NULL)
    return 0;

  frida_session_detach_sync (session, NULL, &error);
  if (error != NULL)
  {
    int rc = copy_gerror (err, err_len, &error);
    frida_unref (session);
    return rc;
  }
  frida_unref (session);
  return 0;
}

int fcb_detach (char * err, int err_len)
{
  pthread_mutex_lock (&g_call_lock);
  int rc = fcb_detach_locked (err, err_len);
  pthread_mutex_unlock (&g_call_lock);
  return rc;
}

int fcb_is_connected (void)
{
  pthread_mutex_lock(&g_lock);
  int connected = (g_session != NULL);
  pthread_mutex_unlock(&g_lock);
  return connected;
}

void fcb_set_message_callback (fcb_message_fn cb, void * user_data)
{
  pthread_mutex_lock(&g_lock);
  g_msg_cb = cb;
  g_msg_ctx = user_data;
  pthread_mutex_unlock(&g_lock);
}

void fcb_set_state_callback (fcb_state_fn cb, void * user_data)
{
  pthread_mutex_lock(&g_lock);
  g_state_cb = cb;
  g_state_ctx = user_data;
  pthread_mutex_unlock(&g_lock);
}

const char * fcb_version_string (void)
{
  return frida_version_string ();
}

const char * fcb_last_error (void)
{
  return g_last_error;
}
