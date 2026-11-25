# jinOS on the OnePlus 6 (enchilada)

The `oneplus6` mkosi profile (`../../mkosi.profiles/oneplus6.conf`) builds
jinOS for the OnePlus 6: the same system as the VM image, on arm64, with
Mobian's sdm845 kernel (6.18) and Qualcomm support packages.

Status: builds, and the image boots to a login prompt under arm64 emulation
(QEMU `virt`, root on an emulated USB disk labelled `userdata`, with the 6.12
kernel; 6.18 has no drivers for QEMU's virtual hardware). That checks the
initramfs, root mount, first-boot resize and system startup. It has **not**
run on the phone yet: display, touch, modem, Wi-Fi, audio and firmware
extraction are untested.

    cd image && mkosi -f --profile oneplus6 build

The build runs arm64 package scripts under emulation (`qemu-user-binfmt`), so
it takes much longer than the PC image. It produces, in `mkosi.output/`:

| File | Flash to |
|---|---|
| `jinos-oneplus6.boot-enchilada.img` | `boot`: Android boot image (kernel + device tree, initramfs, command line) |
| `jinos-oneplus6.userdata.img` | `userdata`: the ext4 root filesystem |

Not for the OnePlus 6T (fajita): it needs a boot image with a different
device tree.

## Before flashing

- **This wipes the phone.** Flashing `userdata` erases everything on it,
  including the current Ubuntu Touch install and its data.
- The bootloader must be unlocked (it already is if Ubuntu Touch is installed).
- jinOS, like Mobian, loads the modem, Wi-Fi, GPU and audio DSP firmware from
  the phone's own Android partitions (`droid-juicer`, on first boot). Mobian's
  known-good base is OxygenOS 10.3.8 firmware; if hardware doesn't come up,
  restore that with the OnePlus 6 EDL package linked on
  https://wiki.debian.org/InstallingDebianOn/OnePlus/OnePlus6 and flash again.
- Install `fastboot` on the PC (`sudo apt install fastboot`).

## Flashing

Put the phone in fastboot mode: power off, then hold power + volume up until
the green START screen. Connect USB, then from `image/`:

    devices/oneplus6/flash.sh

The script checks that a single unlocked OnePlus 6 is in fastboot mode, asks
you to type `wipe`, and runs the commands below (`--slot b` for slot b). By
hand:

    fastboot devices                      # the phone must be listed
    fastboot --set-active=a
    fastboot flash boot jinos-oneplus6.boot-enchilada.img
    fastboot erase userdata
    fastboot -S 100M flash userdata jinos-oneplus6.userdata.img
    fastboot erase dtbo
    fastboot reboot

`-S 100M` sends the root filesystem in sparse 100 MB pieces. `erase dtbo`
removes Android's device-tree overlay, which would otherwise be applied on top
of jinOS's device tree. If the phone stops responding after a command that
succeeded, power it off, enter fastboot mode again and run the remaining
commands.

First boot grows the filesystem to the whole userdata partition, then
`droid-juicer` copies the modem, Wi-Fi, GPU and DSP firmware out of the
phone's Android partitions and **reboots once**. Login: `jin` / `1234` (also
the lock-screen PIN).

## Debugging

Over the USB cable the phone is a network adapter at `10.66.0.1`
(`mobile-usb-networking`):

    ssh jin@10.66.0.1

Password login over SSH is only accepted from that USB network
(`mkosi.extra/etc/ssh/sshd_config.d/jinos.conf`).

Useful on the phone: `journalctl -b`, `systemctl --failed`,
`mmcli -m any` (modem), `nmcli` (Wi-Fi), `dmesg | grep -i -E 'firmware|remoteproc'`.

## Phone features in this build

| Feature | How |
|---|---|
| Ringtone, vibration, notification LED | `feedbackd` with `feedbackd-device-themes` (Calls and Chats only link the library) |
| Rotation, proximity during calls, light sensor | `hexagonrpcd` talks to the sensor DSP using the files `droid-juicer` extracts; `iio-sensor-proxy` reads them via libssc |
| Camera | Plasma Camera on libcamera (`libcamera-ipa`, `pipewire-libcamera`); first icon on the home screen |
| Call audio | `60-jinos-call-audio.conf` stops WirePlumber idle-suspending the sound card, which would silence calls (the modem carries call audio, so PipeWire sees no stream) |
| Call audio after suspend | `jinos-q6voiced-resume.service` restarts `q6voiced` on resume |
| Wake for calls/SMS | `90-jinos-modem-wakeup.rules` |

## How it works

- `mkosi.sandbox/` gives the build Mobian's repository and key
  (fingerprint `D569 936C 7E32 F193 CBAA EC48 393F 924A 855F B27D`);
  `mkosi.extra/` puts the same files in the phone's apt sources.
  `preferences.d/mobian` keeps Debian in charge: Mobian packages install only
  where Debian has none (kernel, support packages), plus Mobian's phone audio
  profiles (`alsa-ucm-conf`).
- `postinst.chroot` builds the boot image as Mobian does: `vmlinuz` (a gzip
  Image) with `sdm845-oneplus-enchilada.dtb` appended, the initramfs, header
  v0 offsets, and the command line
  `mobile.root=PARTLABEL=userdata mobile.qcomsoc=qcom/sdm845 mobile.vendor=oneplus mobile.model=enchilada mobile.rw`.
  The initramfs (initramfs-tools with qcom-phone-utils' `mobile-root`
  script) mounts `userdata` as root.
- After a kernel upgrade on the phone, qcom-phone-utils'
  `/etc/kernel/postinst.d/zz-qcom-bootimg` rebuilds the boot image from those
  `mobile.*` parameters and writes it to the active boot slot.
- `postoutput` publishes the root partition (`SplitArtifacts=partitions`) as
  the userdata image.
- Kernel: `linux-image-6.18-sdm845` with `qcom-support-common`, which is what
  Mobian's current `sdm845-support` installs (its forky snapshot still pins
  6.12).
- `hooks/jinos-adreno-firmware` puts the Adreno 630 GPU firmware in the
  initramfs; initramfs-tools found it from the 6.12 module but not from
  6.18's compressed one.
- `/etc/fstab` grows the root filesystem on first boot (`x-systemd.growfs`).
- `90-jinos-modem-wakeup.rules` lets the modem wake the phone for calls/SMS.

## Known limits (from Mobian's notes for this phone)

- Voice calls are not fully reliable; suspend has issues (power use, audio
  after resume).
- The 3.5 mm jack is only detected if headphones are plugged in at boot.
- Keeping the sound card awake costs some battery; Mobian toggles it per call
  instead, which jinOS could do later.
