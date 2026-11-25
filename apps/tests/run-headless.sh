#!/bin/sh
# Run a jinOS app on this computer for testing, without a VM and without a
# window on your desktop. GTK's Broadway backend draws the app into a web
# page: open http://127.0.0.1:8085 in a browser to see and use it.
#
#   tests/run-headless.sh contacts      (or: about)
#   tests/run-headless.sh contacts --seed   start with three sample contacts
#
# The app gets its own session bus and temporary home, config and data
# folders, so Contacts uses a throwaway address book, never your real one.
# Stop with Ctrl+C.
#
# Needs gtk4-broadwayd (libgtk-4-bin). For Contacts on a host without the
# Evolution Data Server Python bindings, set GI_TYPELIB_PATH to typelibs
# copied from a jinOS image.
set -eu
app=${1:?usage: run-headless.sh contacts|about [--seed]}
seed=${2:-}
apps=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-8085}
display=:${DISPLAY_NUMBER:-5}

case "$app" in
    contacts) module=jinos_contacts.main ;;
    about) module=jinos_about.main ;;
    *) echo "unknown app: $app" >&2; exit 2 ;;
esac

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/jinos-headless.XXXXXX")
mkdir -m 700 "$sandbox/run"
cleanup() {
    [ -n "${broadway:-}" ] && kill "$broadway" 2>/dev/null || true
    rm -rf "$sandbox"
}
trap cleanup EXIT INT TERM

# Broadway puts its socket in XDG_RUNTIME_DIR; it must be the same one the app sees.
XDG_RUNTIME_DIR="$sandbox/run" gtk4-broadwayd --address 127.0.0.1 --port "$port" "$display" &
broadway=$!
sleep 1
echo "Open http://127.0.0.1:$port to see $app"

env -u DISPLAY -u WAYLAND_DISPLAY HOME="$sandbox" \
    XDG_CONFIG_HOME="$sandbox/config" \
    XDG_DATA_HOME="$sandbox/data" \
    XDG_CACHE_HOME="$sandbox/cache" \
    XDG_RUNTIME_DIR="$sandbox/run" \
    GIO_USE_VFS=local \
    GVFS_DISABLE_FUSE=1 \
    GDK_BACKEND=broadway \
    BROADWAY_DISPLAY="$display" \
    PYTHONPATH="$apps/$app:$apps/jinos_ui${PYTHONPATH:+:$PYTHONPATH}" \
    JINOS_SEED="$seed" \
    dbus-run-session -- python3 -c "
import os
if os.environ.get('JINOS_SEED') == '--seed':
    from jinos_contacts.store import Entry, Person, Store
    store = Store()
    for name, number in (('Grace Hopper', '+1 202 555 0143'), ('Ada Lovelace', '+44 20 7946 0018'), ('Alan Turing', '+44 161 555 0199')):
        store.save(Person(name=name, phones=[Entry('CELL', number)]))
from $module import main
raise SystemExit(main())
"
