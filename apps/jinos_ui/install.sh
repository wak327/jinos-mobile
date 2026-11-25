#!/bin/sh
# Install the jinos_ui library into the root directory given as $1 (default /).
set -eu
root=${1:-/}
here=$(dirname "$0")

install -d "$root/usr/lib/python3/dist-packages/jinos_ui"
install -m 644 "$here"/jinos_ui/*.py "$here"/jinos_ui/*.css "$root/usr/lib/python3/dist-packages/jinos_ui/"
