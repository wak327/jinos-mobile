# jinOS image

Debian forky + Plasma Mobile with jinOS Home, built with [mkosi](https://github.com/systemd/mkosi).

Status: the x86-64 image builds (about 2 minutes with a warm cache) and
boots straight to jinOS Home in a VM, dark and phone-sized, with no setup
wizard. The OnePlus 6 image (arm64) builds in about 10 minutes and boots to a
login prompt under arm64 emulation; it has not been on the phone yet (see
`devices/oneplus6/README.md`).

## Host setup (Ubuntu 26.04)

    sudo apt install mkosi debian-archive-keyring qemu-system-arm qemu-efi-aarch64 qemu-user-binfmt

Ubuntu blocks capabilities inside unprivileged user namespaces unless a
program has an AppArmor profile allowing it, so mkosi fails with
"prctl: Operation not permitted". Install the profile in `host/`:

    sudo install -m 644 host/apparmor-mkosi /etc/apparmor.d/mkosi
    sudo apparmor_parser -r /etc/apparmor.d/mkosi

## Build and run

    mkosi -f build         # jinOS: Plasma Mobile + jinOS Home -> mkosi.output/jinos.raw
                           # (-f replaces the previous image; without it mkosi stops)
    ./run-vm.sh            # run it as a phone: portrait 720x1440, GPU-accelerated window

    mkosi -f --architecture=arm64 build   # phone architecture, emulated on x86-64 (untested)

`run-vm.sh` grows the image file to 32 GB (sparse: it only uses host disk
space as it fills), and jinOS grows its root partition and filesystem into it
at boot (`grow-root/`, `mkosi.conf.d/grow-root.conf`), so there is room to
`apt install` software in the VM.

Use `./run-vm.sh`, not `mkosi vm`. mkosi's own window is landscape, has no
3D acceleration (slow) and only a relative mouse, and passing it an extra
display device gives the VM two screens. `run-vm.sh` options: `--phosh`
(the Phosh variant), `--fresh` (throw away changes when the VM stops),
`--touch` (emulated touchscreen). Don't rebuild while the VM is running.

Login is `jin` / `1234` (development only; the password is also the lock-screen PIN and the sudo password).

Install software on a running jinOS with apt as usual (`sudo apt install ...`). mkosi writes the apt sources (forky, forky-updates, forky-security, with `main` and `non-free-firmware`); change components with `Repositories=` in `mkosi.conf`, not by adding a sources file, or apt warns about duplicates. Packages installed this way are lost when the image is rebuilt and reflashed; add anything permanent to `Packages=` in `mkosi.conf`.

## Shell variants

| Command | Image | Shell |
|---|---|---|
| `mkosi -f build` | `jinos.raw` | Plasma Mobile with jinOS Home (default) |
| `mkosi -f --profile phosh build` | `jinos-phosh.raw` | Phosh |
| `mkosi -f --profile oneplus6 build` | `jinos-oneplus6.*` | Plasma Mobile on the OnePlus 6; see `devices/oneplus6/README.md` |
| `mkosi -f --profile laptop build` | `jinos-laptop.raw` | Plasma Desktop for Intel laptops, with an installer; see `devices/laptop/README.md` |

Plasma notes:
- `shells/plasma/` holds the Plasma variant's files and its post-install
  script, which installs jinOS Home (`../shell/home`) as the home screen.
- `plasma-mobile.service` starts the session on tty7, like Debian's phosh.service.
- `qt6-svg-plugins` is required: without it Qt draws no icons and the panels stay empty.
- First-boot defaults come from `/etc/skel/.config`: dark theme, 200% scale
  for the VM's screen, and the setup wizard marked done.
- The on-screen keyboard (`plasma-keyboard`) only appears in tablet mode,
  which KWin enables when it sees a touchscreen; a VM with a mouse-style
  pointer stays in laptop mode.

## Browsers and fonts

- **Firefox ESR** is the default browser, in the dock. `firefox-esr-mobile-config`
  (the phone layout postmarketOS and Mobian use) puts the address bar and tabs
  at the bottom and tells sites it is a phone, so they send their mobile
  layout. Default for web links via `/etc/skel/.config/mimeapps.list` and
  KDE's `BrowserApplication` in `kdeglobals`.
- GNOME Web was tried as a second browser and dropped: pages laid out
  wrongly (its own welcome page squeezed into a narrow serif column,
  Wikipedia's search box collapsed), with or without GPU acceleration. Qt also
  drew its SVG icon on a black square, because of `<clipPath>` elements.
- Chromium was tried first and dropped: its window can't be narrower than 500
  points (a phone screen is about 360), it opens a KDE Wallet wizard on first
  start, and it sends desktop layouts.
- Fonts: Noto core (most scripts, including Urdu), Noto CJK (Chinese,
  Japanese, Korean) and Noto Color Emoji. Without them those scripts show as
  empty boxes.

## Phone and messages

GNOME Calls ("Phone") and Chatty ("Chats"), in the dock
(`mkosi.conf.d/telephony.conf`). They read names from Evolution Data Server,
where jinOS Contacts stores contacts; that needs `libfolks-eds26`, which is
only recommended and so had to be listed. Both start background daemons at
login (`/etc/xdg/autostart`) so calls and messages arrive with the apps
closed. `callaudiod` routes call audio, `mmsd-tng` handles picture messages.
In the VM they report "No modem".

## Utilities

`mkosi.conf.d/utilities.conf`: Plasma Mobile's Clock, Calculator, Weather,
Calendar (Calindori), Okular Mobile, Recorder, Photos (Koko), Keysmith (2FA)
and Qrca (QR codes), GNOME Text Editor and Maps, and command-line tools
(htop, git, curl, wget, unzip, tree). Clock, Calendar, Weather and Calculator
are on the default home screen.

- Default apps for files (`/etc/skel/.config/mimeapps.list`): Okular registers
  for text and images too, so text goes to Text Editor and photos to Photos.
- Terminal apps such as Htop open in GNOME Console: Plasma's default terminal,
  Konsole, isn't installed (`TerminalApplication`/`TerminalService` in
  `kdeglobals`).

## Files

GNOME Files (`nautilus`) is the file manager, on the home screen. KDE's own
phone file manager, Index, isn't in Debian. jinOS defaults
(`90_jinos.gschema.override`): a tap opens a file or folder (GNOME's default
needs a double tap) and a smaller grid, so a phone screen shows all the home
folders. Its search uses `localsearch`, an indexer that runs in the background.

GTK apps get their icon theme from the settings portal. KDE's portal doesn't
provide one, and without `xdg-desktop-portal-gtk` (only recommended, so
skipped) GTK fell back to a theme called "gnome" that doesn't exist: missing
icons and huge grey folders. KDE's `kde-portals.conf` already lists the GTK
backend second, so installing it fixes every GTK app. jinOS's own apps were
unaffected because `jinos_ui` sets Adwaita itself.

## Settings for this computer

`mkosi.local.conf` (not committed) holds settings for this computer only:
the dev images' timezone, and `Mirror=` when `deb.debian.org` is slow from
your network. mkosi uses the mirror only while building; the image's own apt
sources keep `deb.debian.org`.

## Layout

- `mkosi.conf` - base image: packages, VM settings
- `mkosi.conf.d/` - per-architecture kernel
- `mkosi.conf.d/shell-plasma.conf`, `mkosi.profiles/phosh.conf` - the two shell variants
- `mkosi.conf.d/telephony.conf`, `mkosi.conf.d/utilities.conf` - phone, messages and utility apps
- `mkosi.profiles/oneplus6.conf`, `devices/oneplus6/` - the OnePlus 6 build
- `mkosi.profiles/laptop.conf`, `devices/laptop/`, `shells/desktop/` - the laptop build and installer
- `scripts/postinst.chroot` - creates the uid-1000 user the shell runs as, copies `/etc/skel` into its home, and installs the apps in `../apps`
- `run-vm.sh` - runs a built image as a phone-shaped VM
- `mkosi.extra/` - files copied into the image: service presets, GSettings defaults (on-screen keyboard on), and a tmpfiles rule that fixes the home directory's ownership at boot (unprivileged builds store every file as root)

## Fixes found during first boot

- `InitrdPackages=mount`: mkosi 26's default initrd lacks Debian's separate `mount` package, so the root partition never mounted.
- `kbd`: phosh.service runs `chvt`.
- `tmpfiles.d/jinos-home.conf`: see above.
- `useradd --create-home` stops copying `/etc/skel` at the first file it
  can't chown, which is always in an unprivileged build; the post-install
  script copies it itself.

## Testing notes

- `./run-vm.sh --touch` gives the VM a touchscreen; Plasma then switches to
  tablet mode and the on-screen keyboard appears in text fields (verified in
  Firefox and the app drawer's search). Sending touches over QMP
  (`input-send-event`, `mtt` events): the finger only lifts when the `end`
  event carries `tracking-id` -1.
- QEMU's `screendump` fails on GPU-accelerated displays ("no surface"). To
  capture one, start QEMU with `-display egl-headless -vnc unix:<socket>` and
  read a frame over VNC.
- Apps: GNOME Console (`gnome-console`) is the terminal. The on-screen keyboard is Stevia (`phosh-osk-stevia`, pulled in by `phosh-core`); it switches to a terminal layout with Esc, Ctrl, Alt and arrows.
- In the VM the on-screen keyboard stays hidden, most likely because QEMU attaches a hardware keyboard. To show it: `busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true`.
- The VM needs `-device virtio-keyboard-pci` to accept QEMU `sendkey` input, because mkosi starts QEMU without default devices.
- `pgrep stevia` finds nothing: process names are cut to 15 characters (`phosh-osk-stevi`). Use `pgrep -f stevia`.

## Not here yet

- CI
- Updates and rollback (RAUC)
