//
//  FridaCoreBridge.h
//  TrollReverseLab
//
//  Thin C wrapper over frida-core (devkit static lib) for Swift.
//  All GLib/frida types stay inside the .c file — Swift only sees
//  opaque handles, error buffers and C function pointers.
//
//  Link: libfrida-core.a + -lbsm -lresolv (devkit 17.17.0 ios-arm64)
//

#ifndef FRIDA_CORE_BRIDGE_H
#define FRIDA_CORE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// message callback — fires on the GLib loop thread.
/// json_message = full Frida message JSON string ({"type":"log|send|error", ...})
typedef void (*fcb_message_fn)(const char *json_message, void *user_data);

/// session state callback — fires on the GLib loop thread when detached.
/// reason: 1=application_requested 2=process_replaced 3=process_terminated
///         4=connection_terminated 5=device_lost
typedef void (*fcb_state_fn)(int detach_reason, void *user_data);

/// One-time init: frida_init + dedicated GLib main-loop thread + device
/// manager + local device lookup. Idempotent.
/// @return 0 on success, negative on failure (err buffer filled)
int fcb_init(char *err, int err_len);

void fcb_set_message_callback(fcb_message_fn cb, void *user_data);
void fcb_set_state_callback(fcb_state_fn cb, void *user_data);

/// Attach to pid on the local device.
/// @return 0 on success, negative on failure (err buffer filled)
int fcb_attach(uint32_t pid, char *err, int err_len);

/// Create + load a QJS script on the attached session. Replaces any
/// previously loaded script (unload first).
/// @return 0 on success, negative on failure (err buffer filled)
int fcb_load_script(const char *source, char *err, int err_len);

/// Unload + destroy current script (no-op when none loaded).
/// @return 0 on success, negative on failure (err buffer filled)
int fcb_unload_script(char *err, int err_len);

/// Unload script, detach session, drop handles. Device manager stays alive
/// for the next attach.
/// @return 0 on success, negative on failure (err buffer filled)
int fcb_detach(char *err, int err_len);

/// 1 when a live session exists, 0 otherwise.
int fcb_is_connected(void);

/// frida_version_string() passthrough, e.g. "17.17.0".
const char *fcb_version_string(void);

/// Last error detail (static buffer, overwritten by every failing call).
const char *fcb_last_error(void);

#ifdef __cplusplus
}
#endif

#endif /* FRIDA_CORE_BRIDGE_H */
