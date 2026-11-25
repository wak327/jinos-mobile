#!/bin/sh
# Run a built jinOS image as a phone-shaped VM.
#
#   ./run-vm.sh                 jinOS (jinos.raw: Plasma Mobile + jinOS Home), window on screen
#   ./run-vm.sh --phosh         the Phosh variant (jinos-phosh.raw)
#   ./run-vm.sh --fresh         throw away changes when the VM stops
#                               (the image file is grown to 32 GB, sparse, so apt has room)
#   ./run-vm.sh --touch         emulate a touchscreen instead of a pointer
#   ./run-vm.sh --laptop        the laptop build as a laptop: 1280x800 screen, the
#                               live ISO in a DVD drive and a 32 GB disk
#                               (mkosi.output/jinos-laptop-vm.qcow2) to install to
#                               with jinos-install. Once installed, it boots the disk.
#   ./run-vm.sh --laptop --reset  start the laptop VM over with an empty disk
#   ./run-vm.sh -- <args>       extra QEMU arguments
#
# Unlike `mkosi vm` this gives a 720x1440 portrait screen, GPU acceleration
# (virtio-vga-gl) and an absolute pointer, so clicks land where you click.
# Don't rebuild the image while the VM is running.
set -eu
cd "$(dirname "$0")"

image=mkosi.output/jinos.raw
gpu="virtio-vga-gl"
display="sdl,gl=on"
pointer=virtio-tablet-pci
snapshot=""
laptop=""
reset=""
while [ $# -gt 0 ]; do
    case "$1" in
        --phosh) image=mkosi.output/jinos-phosh.raw ;;
        --fresh) snapshot="-snapshot" ;;
        --touch) pointer=virtio-multitouch-pci ;;
        --laptop) laptop=1 ;;
        --reset) reset=1 ;;
        # For automated tests: no window and no GPU acceleration, because QEMU's
        # screendump waits for a new frame on accelerated displays and an idle
        # screen never draws one.
        --headless) gpu="virtio-vga"; display="none" ;;
        --) shift; break ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

timezone=$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)

if [ -n "$laptop" ]; then
    iso=mkosi.output/jinos-laptop.iso
    disk=mkosi.output/jinos-laptop-vm.qcow2
    vars=mkosi.output/jinos-laptop-vm.vars
    [ -f "$iso" ] || { echo "$iso not found; build it first (mkosi -f --profile laptop build)" >&2; exit 1; }
    if [ -n "$reset" ] || [ ! -f "$disk" ]; then
        rm -f "$disk" "$vars"
        qemu-img create -q -f qcow2 "$disk" 32G
    fi
    # Kept with the disk: the firmware's boot entries, as on a real laptop.
    [ -f "$vars" ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"
    # The disk is tried first; while it is empty the firmware falls back to the ISO.
    exec qemu-system-x86_64 \
        -machine q35,accel=kvm -cpu host -smp 4 -m 6G \
        -name "jinOS laptop" \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
        -drive if=pflash,format=raw,file="$vars" \
        -drive if=none,id=disk,format=qcow2,file="$disk",discard=unmap \
        -device nvme,drive=disk,serial=jinos-laptop,bootindex=1 \
        -drive if=none,id=cd,media=cdrom,readonly=on,file="$iso" \
        -device ide-cd,drive=cd,bootindex=2 \
        -device "$gpu",xres=1280,yres=800 -display "$display" \
        -device virtio-keyboard-pci -device virtio-tablet-pci \
        -device virtio-rng-pci \
        -device intel-hda -device hda-duplex \
        -nic user,model=virtio-net-pci \
        -smbios type=11,value=io.systemd.credential:firstboot.timezone="$timezone" \
        "$@"
fi

[ -f "$image" ] || { echo "$image not found; build it first (mkosi build)" >&2; exit 1; }

# Give the image room to install software: grow the file to 32 GB (sparse, so
# it only takes host disk space as it fills). systemd-repart in the image grows
# the root partition and filesystem into it at boot (grow-root/).
[ "$(stat -c %s "$image")" -ge $((32 * 1024 * 1024 * 1024)) ] || truncate -s 32G "$image"

vars=$(mktemp "${TMPDIR:-/tmp}/jinos-ovmf-vars.XXXXXX")
trap 'rm -f "$vars"' EXIT
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$vars"

qemu-system-x86_64 \
    -machine q35,accel=kvm -cpu host -smp 4 -m 4G \
    -name jinOS \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file="$vars" \
    -drive file="$image",format=raw,if=virtio,discard=unmap $snapshot \
    -device "$gpu",xres=720,yres=1440 -display "$display" \
    -device virtio-keyboard-pci -device "$pointer" \
    -device virtio-rng-pci \
    -nic user,model=virtio-net-pci \
    -smbios type=11,value=io.systemd.credential:firstboot.timezone="$timezone" \
    "$@"
