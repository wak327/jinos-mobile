#!/bin/sh
# Run the store test against a private Evolution Data Server: its own
# session bus and its own temporary data folders. Your real address book
# is never touched.
#
# On a host without the EDS Python bindings, point GI_TYPELIB_PATH at
# typelibs copied from a jinOS image.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/jinos-contacts-test.XXXXXX")
trap 'rm -rf "$sandbox"' EXIT
mkdir -m 700 "$sandbox/run"

env HOME="$sandbox" \
    XDG_CONFIG_HOME="$sandbox/config" \
    XDG_DATA_HOME="$sandbox/data" \
    XDG_CACHE_HOME="$sandbox/cache" \
    XDG_RUNTIME_DIR="$sandbox/run" \
    GIO_USE_VFS=local \
    GVFS_DISABLE_FUSE=1 \
    JINOS_TEST_SANDBOX=1 \
    dbus-run-session -- python3 "$here/test_store.py"
