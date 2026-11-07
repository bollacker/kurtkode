#!/bin/bash
# Runs "$@" under kurtkode's default command sandbox (SandboxPolicy(): no network, no extra folders), workspace = $WS.
real() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
PROFILE='(version 1)
(allow default)
(deny file-write* (with message (param "TAG")))
(allow file-write*
    (subpath (param "WORKSPACE"))
    (subpath (param "TMPDIR"))
    (subpath (param "CACHEDIR"))
    (subpath "/private/tmp")
    (subpath "/private/var/tmp")
    (literal "/dev/null") (literal "/dev/zero") (literal "/dev/tty") (literal "/dev/dtracehelper")
    (regex #"^/dev/fd/[0-9]+$") (regex #"^/dev/ttys[0-9]+$"))
(deny file-write* (with message (param "TAG"))
    (subpath (string-append (param "WORKSPACE") "/.git/hooks"))
    (literal (string-append (param "WORKSPACE") "/.git/config")))
(deny network* (with message (param "TAG")))'
cd "$WS" && exec /usr/bin/sandbox-exec -p "$PROFILE" -D WORKSPACE="$(real "$WS")" -D TMPDIR="$(real "$(getconf DARWIN_USER_TEMP_DIR)")" \
  -D CACHEDIR="$(real "$(getconf DARWIN_USER_CACHE_DIR)")" -D TAG=kkswiftcheck /bin/zsh -c "$*"
