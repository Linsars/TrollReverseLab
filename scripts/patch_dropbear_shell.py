#!/usr/bin/env python3
"""CI patch: dropbear for iOS.

1) get_user_shell(): /etc/passwd lists mobile's shell as /bin/sh but iOS
   ships no /bin/sh (bootstrap shell lives at /var/jb/bin/sh). Probe
   candidates, return the first executable one — otherwise sessions
   authenticate then hang silently on exec.
2) DEFAULT_PATH: dropbear's compiled-in "/usr/bin:/bin" is useless on a
   bare iOS system (no ls/id there). Bootstrap paths first, system after.

Usage: patch_dropbear_shell.py <dropbear-source-root>
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else "."

cs = os.path.join(root, "src", "common-session.c")
s = open(cs).read()
old = '''const char* get_user_shell() {
\t/* an empty shell should be interpreted as "/bin/sh" */
\tif (ses.authstate.pw_shell[0] == '\\0') {
\t\treturn "/bin/sh";
\t} else {
\t\treturn ses.authstate.pw_shell;
\t}
}'''
new = '''const char* get_user_shell() {
\t/* iOS: passwd shell (/bin/sh) may not exist. Pick the first executable shell. */
\tstatic const char* candidates[] = { NULL, "/var/jb/bin/sh", "/var/jb/bin/zsh", "/bin/sh", NULL };
\tstatic char shellbuf[256];
\tif (ses.authstate.pw_shell[0] != '\\0') {
\t\tcandidates[0] = ses.authstate.pw_shell;
\t} else {
\t\tcandidates[0] = "/bin/sh";
\t}
\tfor (int i = 0; candidates[i]; i++) {
\t\tif (access(candidates[i], X_OK) == 0) {
\t\t\tstrlcpy(shellbuf, candidates[i], sizeof(shellbuf));
\t\t\treturn shellbuf;
\t\t}
\t}
\treturn "/bin/sh";
}'''
assert old in s, "shell anchor not found in %s — dropbear version drift?" % cs
open(cs, "w").write(s.replace(old, new))
print("patched get_user_shell OK ->", cs)

do = os.path.join(root, "src", "default_options.h")
s = open(do).read()
oldp = '#define DEFAULT_PATH "/usr/bin:/bin"'
newp = '#define DEFAULT_PATH "/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin"'
assert oldp in s, "PATH anchor not found in %s — dropbear version drift?" % do
open(do, "w").write(s.replace(oldp, newp))
print("patched DEFAULT_PATH OK ->", do)
