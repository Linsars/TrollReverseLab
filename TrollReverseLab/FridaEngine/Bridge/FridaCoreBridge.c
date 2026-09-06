//
//  FridaCoreBridge.c
//  TrollReverseLab
//
//  Real frida-core embedding (devkit 17.17.0, ios-arm64).
//  Dedicated GLib loop thread + device manager + local device.
//  API flow mirrors the official frida-core-example.c.
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
static volatile gboolean g_init_failed = FALSE;   // loop 线程启动失败标志（g_main_loop_is_running 在 run 前恒 FALSE，不能当存活判据）

static void set_last_error(const char *msg)
{
  if (msg == NULL) msg = "unknown error";
  pthread_mutex_lock(&g_lock);
  snprintf(g_last_error, sizeof (g_last_error), "%s", msg);
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
  const char *msg = (errorp != NULL && *errorp != NULL) ? (*errorp)->message : "unknown frida error";
  if (errorp != NULL && *errorp != NULL)
  {
    g_printerr ("[fcb] frida error: %s\n", (*errorp)->message);
    g_error_free (*errorp);
    *errorp = NULL;
  }
  return copy_err(err, err_len, msg);
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
  if (g_script != NULL) { g_script = NULL; }
  if (g_session != NULL) { g_session = NULL; }
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

// MARK: - init thread

static gpointer loop_thread_func (gpointer user_data)
{
  GError * error = NULL;
  FridaDeviceList * devices;
  gint num_devices, i;
  (void) user_data;

  frida_init ();

  g_manager = frida_device_manager_new ();

  devices = frida_device_manager_enumerate_devices_sync (g_manager, NULL, &error);
  if (error != NULL)
  {
    g_init_failed = TRUE;
    copy_gerror (NULL, 0, &error);
    g_printerr ("[fcb] device enumeration failed, loop thread exiting\n");
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
    g_init_failed = TRUE;
    copy_err (NULL, 0, "local device not found");
    g_printerr ("[fcb] no local device, loop thread exiting\n");
    return NULL;
  }

  g_printerr ("[fcb] frida-core %s ready, local device acquired\n", frida_version_string ());

  g_main_loop_run (g_loop);   // runs forever
  return NULL;
}

// MARK: - public API

int fcb_init (char * err, int err_len)
{
  pthread_t tid;

  pthread_mutex_lock(&g_lock);
  gboolean already = (g_loop != NULL);
  pthread_mutex_unlock(&g_lock);
  if (already)
    return 0;

  g_loop = g_main_loop_new (NULL, TRUE);
  if (pthread_create (&tid, NULL, loop_thread_func, NULL) != 0)
    return copy_err (err, err_len, "failed to spawn frida loop thread");
  pthread_detach (tid);

  // 设备枚举在子线程异步完成——最多等 5 秒确认就绪
  for (int i = 0; i < 50; i++)
  {
    usleep (100 * 1000);
    if (g_init_failed)
      return copy_err (err, err_len, fcb_last_error ());
    pthread_mutex_lock(&g_lock);
    gboolean ready = (g_local_device != NULL);
    pthread_mutex_unlock(&g_lock);
    if (ready)
      return 0;
  }
  return copy_err (err, err_len, "frida-core init timeout (no local device in 5s)");
}

int fcb_attach (uint32_t pid, char * err, int err_len)
{
  GError * error = NULL;
  FridaSession * session;
  FridaDevice * device;

  if (fcb_init (err, err_len) != 0)
    return -1;

  // 引擎层可能重复 attach（新 bridge 实例）——C 层全局状态，先清干净旧会话
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

int fcb_load_script (const char * source, char * err, int err_len)
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

int fcb_unload_script (char * err, int err_len)
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

int fcb_detach (char * err, int err_len)
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
