#!/bin/sh
# Install Contacts into the root directory given as $1 (default /).
set -eu
root=${1:-/}
here=$(dirname "$0")

install -d "$root/usr/lib/python3/dist-packages/jinos_contacts"
install -m 644 "$here"/jinos_contacts/*.py "$root/usr/lib/python3/dist-packages/jinos_contacts/"
install -D -m 755 "$here/jinos-contacts" "$root/usr/bin/jinos-contacts"
install -D -m 644 "$here/org.jinos.Contacts.desktop" "$root/usr/share/applications/org.jinos.Contacts.desktop"
install -D -m 644 "$here/org.jinos.Contacts.svg" "$root/usr/share/icons/hicolor/scalable/apps/org.jinos.Contacts.svg"
