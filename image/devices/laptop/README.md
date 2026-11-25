# jinOS on a laptop

The `laptop` mkosi profile (`../../mkosi.profiles/laptop.conf`) builds jinOS
for Intel laptops: the same Debian forky system, apps and settings as the
phone builds, with Plasma Desktop and the SDDM login screen instead of Plasma
Mobile, firmware for Intel Wi-Fi/Bluetooth, graphics and audio, and no phone
apps (Calls, Chats).

    cd image && mkosi -f --profile laptop build

This makes two files in `mkosi.output/`:

| File | Size | What |
|---|---|---|
| `jinos-laptop.iso` | 1.4 GB | Live ISO: boot it from a USB stick or DVD, try jinOS, install it |
| `jinos-laptop.raw` | 6 GB | Disk image of the same system (also bootable from a USB stick) |

Use the ISO. Tested in a VM (QEMU, UEFI): boot the ISO, install to an NVMe
disk, boot the installed system, add a second kernel. Not yet tried on a real
laptop.

## 1. Write the ISO to a USB stick (4 GB or more)

Find the stick's device name with `lsblk` (e.g. `/dev/sdb`; **double-check
it, everything on it is erased**), then:

    sudo dd if=mkosi.output/jinos-laptop.iso of=/dev/sdX bs=4M conv=fsync status=progress

Tools like Ventoy, balenaEtcher or GNOME Disks work too. The ISO is UEFI-only.

## 2. Prepare the laptop

In the firmware setup (usually F2, F10, F12 or Del at power-on):

- Turn **Secure Boot off**: jinOS isn't signed yet.
- Make sure it boots in UEFI mode (not "Legacy/CSM").

## 3. Try it from the stick

Boot from the stick (the one-time boot menu key is often F12). jinOS starts
as a live system: nothing is written to the laptop or the stick, and changes
are lost at shutdown. Log in as `jin` with password `1234` and check that
Wi-Fi, sound, the touchpad and the screen work.

## 4. Install

In the live system, open Console and run:

    sudo jinos-install                 # lists the disks
    sudo jinos-install /dev/nvme0n1    # the laptop's disk; ERASES IT

It refuses to install onto the stick itself, asks you to type the disk name,
and asks for a new password for `jin`. Then it:

- creates a 1 GB EFI system partition and copies the root filesystem block
  for block into the rest of the disk, then grows it to fill the disk;
- gives the copy a new filesystem UUID and machine ID;
- installs systemd-boot, adds a "Linux Boot Manager" entry to the laptop's
  firmware, and builds the first boot image the same way kernel updates will.

Remove the stick and restart. Log in as `jin` with the password you set.

(The disk image `jinos-laptop.raw` can install too: write it to a stick,
choose **jinOS (Install to this computer)** in its boot menu, which keeps the
stick read-only, and run the same command.)

## Kernel updates

`sudo apt upgrade` installs new Debian kernels like on any Debian system.
Each one gets its own boot image in the EFI partition (`/efi/EFI/Linux`), and
the boot menu shows the newest first, with older ones still there to fall
back to. Hold the space bar at power-on to see the menu. Removing a kernel
package removes its entry.

This is standard Debian and systemd machinery, configured by
`/etc/kernel/install.conf`: apt's `zz-systemd-boot` hook runs `kernel-install`,
which builds an initramfs with dracut and a unified kernel image (UKI) with
ukify. The kernel command line is in `/etc/kernel/cmdline`, written by the
installer.

## How it works

- The ISO (`postinst.chroot`, `postoutput`): a UKI whose dracut initramfs has
  `dmsquash-live`, set as the ISO's EFI boot image; `LiveOS/squashfs.img`
  holds the image's root filesystem. At boot dracut finds the ISO by its label
  `JINOS`, attaches the root filesystem read-only (mounted at
  `/run/rootfsbase`) and runs it under an overlay in RAM. The EFI image is
  inside the ISO filesystem, not appended after it: firmware reads its size
  from the ISO's directory entry, and it is too big for the El Torito header.
- `install.uki-profile` adds "Install to this computer" to the disk image's
  boot menu: the same system booted with `systemd.volatile=overlay`
  (read-only root, changes in RAM).
- `mkosi.extra/usr/sbin/jinos-install` copies the read-only root filesystem
  (the ISO's `/run/rootfsbase` device, or the stick's root partition found
  from the boot loader's `LoaderDevicePartUUID` EFI variable) with
  `systemd-repart` `CopyBlocks=`, then runs `bootctl install` and
  `kernel-install` inside the new system. It's in `/usr/sbin` because Debian's
  sudo doesn't search `/usr/local/sbin`.
- `../../shells/desktop/`: SDDM on a Wayland greeter (no X server), the dark
  theme and default apps, and taskbar pins for apps jinOS ships (Plasma's
  built-in defaults include Discover, which isn't installed).
- `fonts-hack`: Plasma tells GTK apps to use Hack as the monospace font;
  without it Console's text is widely spaced.

## Known limits

- UEFI only; no legacy BIOS boot.
- Secure Boot must be off: the boot images aren't signed.
- No disk encryption yet.
