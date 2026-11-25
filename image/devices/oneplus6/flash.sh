#!/bin/sh
# Flash jinOS to a OnePlus 6 (enchilada) in fastboot mode. ERASES THE PHONE.
#
#   devices/oneplus6/flash.sh            (from image/, after mkosi -f --profile oneplus6 build)
#   devices/oneplus6/flash.sh --slot b   use slot b instead of a
#
# Fastboot mode: power off, then hold power + volume up until the green START
# screen, and connect USB. See README.md in this folder.
set -eu
cd "$(dirname "$0")/../.."

slot=a
while [ $# -gt 0 ]; do
    case "$1" in
        --slot) slot=${2:?}; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
case "$slot" in a|b) ;; *) echo "slot must be a or b" >&2; exit 2 ;; esac

boot=mkosi.output/jinos-oneplus6.boot-enchilada.img
userdata=mkosi.output/jinos-oneplus6.userdata.img

command -v fastboot >/dev/null || { echo "fastboot not found: sudo apt install fastboot" >&2; exit 1; }
for f in "$boot" "$userdata"; do
    [ -f "$f" ] || { echo "$f not found; build it first: mkosi -f --profile oneplus6 build" >&2; exit 1; }
done

echo "Waiting for a phone in fastboot mode..."
devices=$(fastboot devices)
[ -n "$devices" ] || { echo "No phone in fastboot mode found." >&2; exit 1; }
[ "$(echo "$devices" | wc -l)" -eq 1 ] || { echo "More than one fastboot device connected:" >&2; echo "$devices" >&2; exit 1; }

# OnePlus 6 and 6T both report sdm845; the 6T needs a different boot image.
product=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p')
unlocked=$(fastboot getvar unlocked 2>&1 | sed -n 's/^unlocked: *//p')
echo "Phone: product=${product:-?} unlocked=${unlocked:-?}"
case "$product" in
    *sdm845*|*enchilada*|*OnePlus6*) ;;
    *) echo "This doesn't look like a OnePlus 6 (product '$product'); stopping." >&2; exit 1 ;;
esac
[ "$unlocked" = yes ] || { echo "The bootloader is locked; unlock it first (see README.md)." >&2; exit 1; }

cat <<EOF

About to flash jinOS to slot $slot. This ERASES everything on the phone,
including the current OS (Ubuntu Touch) and all its data.
Make sure this is a OnePlus 6, not a 6T.

EOF
printf 'Type "wipe" to continue: '
read -r answer
[ "$answer" = wipe ] || { echo "Cancelled; nothing was changed."; exit 1; }

set -x
fastboot --set-active="$slot"
fastboot flash boot "$boot"
fastboot erase userdata
fastboot -S 100M flash userdata "$userdata"
fastboot erase dtbo
fastboot reboot
set +x

cat <<EOF

Done. First boot grows the filesystem, then extracts firmware from the
Android partitions and reboots once. Login: jin / 1234.
If it doesn't come up, ssh jin@10.66.0.1 over the USB cable and run:
  journalctl -b; systemctl --failed
EOF
