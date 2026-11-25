#!/bin/sh
# Install About Phone into the root directory given as $1 (default /).
set -eu
root=${1:-/}
here=$(dirname "$0")

install -d "$root/usr/lib/python3/dist-packages/jinos_about"
install -m 644 "$here"/jinos_about/*.py "$root/usr/lib/python3/dist-packages/jinos_about/"
install -D -m 755 "$here/jinos-about" "$root/usr/bin/jinos-about"
install -D -m 644 "$here/org.jinos.About.desktop" "$root/usr/share/applications/org.jinos.About.desktop"
install -D -m 644 "$here/org.jinos.About.svg" "$root/usr/share/icons/hicolor/scalable/apps/org.jinos.About.svg"
