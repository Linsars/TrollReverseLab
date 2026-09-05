#!/usr/bin/env python3
"""CI patch: dropbear get_user_shell() for iOS.

/etc/passwd lists mobile's shell as /bin/sh but iOS ships no /bin/sh
(jailbreak bootstrap shell lives at /var/jb/bin/sh). Unpatched dropbear
authenticates fine then silently hangs on exec. This patch makes
get_user_shell() probe candidates and return the first executable one.
"""
import sys

p = sys.argv[1] if len(sys.argv) > 1 else "src/common-session.c"
s = open(p).read()

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

assert old in s, "anchor not found in %s — dropbear version drift?" % p
open(p, "w").write(s.replace(old, new))
print("patched get_user_shell OK ->", p)
