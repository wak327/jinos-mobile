#!/bin/sh
# Install jinOS Home (a Plasma Mobile home screen) into the root directory given as $1 (default /).
set -eu
root=${1:-/}
here=$(dirname "$0")
dest="$root/usr/share/plasma/plasmoids/org.jinos.home"

rm -rf "$dest"
install -d "$dest/contents/ui" "$dest/contents/config"
install -m 644 "$here/metadata.json" "$dest/"
install -m 644 "$here"/contents/ui/*.qml "$here"/contents/ui/*.js "$dest/contents/ui/"
install -m 644 "$here"/contents/config/*.xml "$dest/contents/config/"
