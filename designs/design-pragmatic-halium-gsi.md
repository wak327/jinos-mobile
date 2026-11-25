# Design proposal "Kestrel": hardware-coverage-first via Halium / Treble GSI

Key: `pragmatic-halium-gsi`. Status checks dated 2026-10-02; finalised 2026-10-03. Everything marked **[verified]** was checked against a 2025-2026 primary source linked inline; **[unverified]** means I could not confirm it and the design treats it as a risk, not a fact.

## 0. Thesis in one paragraph

Mainline Linux reaches a phone three to six years after launch; Android's Treble contract reaches it on day one. Kestrel therefore treats the phone's own vendor partitions (`vendor`, `odm`, `vendor_dlkm`, firmware, DSP, `persist`) as the driver layer, runs them unmodified in an LXC container under a stripped Android `init`, and puts an ordinary glibc/systemd/Wayland Linux on top, Droidian/FuriOS style. The port unit is not a device but a *(vendor API level, GKI kernel branch)* pair: one Linux root image, one Halium system image per Halium generation (13, 14, 16), the stock or minimally rebuilt GKI kernel per Android Common Kernel branch, and a small per-device adaptation package generated from the factory image. Three things keep it survivable for 1-3 people: riding FuriLabs' maintained `forky` branches instead of forking, image-based A/B updates with automatic rollback, and a per-device migration path to mainline that swaps only the hardware layer while apps, shell and portals stay put.

## 1. Hardware adaptation

### 1.1 Which devices "boot on day one" and why

Google's Android 17 GSI (18 June 2026) boots on any unlocked Treble device launched with Android 9+ and is validated on every Pixel from the 6 to the 10a ([GSI release notes](https://developer.android.com/about/versions/17/gsi-release-notes)) **[verified]**. A Halium system image is a GSI with the framework removed and HAL glue added, so a device that boots Google's GSI is Treble-clean enough for ours; only kernel and libhybris quirks remain. The compatibility key is the *vendor API level* (`ro.vendor.api_level`, `YYYYMM` format, 202404 for Android 15-era vendors), not the marketing version: Fairphone 5 runs Android 15 on VNDK 30 and is served by Halium 11 ([UBports forum](https://forums.ubports.com/post/89132), [AOSP api-flags](https://source.android.com/docs/core/architecture/api-flags)) **[verified]**.

Target matrix (kernel versions from LineageOS device data unless noted):

| Device | SoC | Launch Android / vendor API | Kernel | Unlock | Kestrel image |
|---|---|---|---|---|---|
| Fairphone 5 | QCM6490 | 13 / VNDK 30 | 5.4 vendor tree | OEM code | Halium 13; UT port at 97.4% ([UT FP5](https://devices.ubuntu-touch.io/device/FP5/release/noble)) |
| Fairphone (Gen. 6) | SM7635 | 15 / **[unverified]** | 6.1 GKI ([LineageOS](https://raw.githubusercontent.com/LineageOS/lineage_wiki/main/_data/devices/FP6.yml)) | OEM code | Halium 14; UBports reference port exists ([forum](https://forums.ubports.com/post/94806)) |
| Pixel 8 / 9 families | Tensor G3 / G4 | 14 / 34 | 6.1 GKI ([LineageOS](https://raw.githubusercontent.com/LineageOS/lineage_wiki/main/_data/devices/shiba.yml), [Pixel kernels](https://source.android.com/docs/setup/build/building-pixel-kernels)) | non-carrier, custom AVB key | Halium 14 |
| Pixel 10 family | Tensor G5 | 16 / 202504 | 6.6 GKI ([GrapheneOS](https://discuss.grapheneos.org/d/27035-multiple-kernels)) | same; GSI-validated | Halium 16 |
| OnePlus 13 | SM8750 | 15 / 202404 | 6.6 GKI ([LineageOS](https://raw.githubusercontent.com/LineageOS/lineage_wiki/main/_data/devices/dodge.yml)) | global yes, China gated ([Notebookcheck](https://www.notebookcheck.net/OnePlus-tightens-ColorOS-bootloader-unlock-policy-adds-device-quota-and-14-day-expiry-window.1350758.0.html)) | Halium 16, secondary |
| Volla Quintus / FLX1s | Dimensity 7050 / 900 | 13-class | 5.10/5.15 vendor | sold unlocked | Halium 13; existing ports |

Excluded on policy: Samsung, Xiaomi, OnePlus China. Pixels stay *developer* targets: kernel source is behind a request form and no device trees have shipped since Android 16 ([OSFY](https://www.opensourceforu.com/2026/08/google-makes-pixel-kernel-source-harder-to-access/)) **[verified]**, so nothing in Kestrel may depend on Google-published device trees (9.1).

### 1.2 Android base versions: three generic Halium images, converging to one

- **Halium 13** (`halium-13.0`, updated 22 Sep 2026): what Droidian 101 and FuriOS ship; vendor API 30-33 devices ([Halium/android branches](https://github.com/Halium/android/branches/all), [Droidian releases](https://github.com/droidian-images/droidian/releases)) **[verified]**.
- **Halium 14** (`halium-14.0`, tree 18 May 2026, `hybris-patches` 4 Sep 2026): UBports' FP6 base; vendor API 34 devices ([hybris-patches](https://github.com/Halium/hybris-patches/branches/all)) **[verified]**.
- **Halium 16** (`halium-16.0`, tree 28 Aug 2026, `hybris-patches` 25 Sep 2026, manifest on LineageOS 23.2 / `android-16.0.0_r4`): the only base for Android 15/16-era vendors and, since newer-system-over-older-vendor is the GSI model, the eventual single image. It is weeks old with no `halium-devices` manifests yet ([manifest](https://raw.githubusercontent.com/Halium/android/halium-16.0/default.xml), [halium-devices](https://github.com/Halium/halium-devices/branches/all)) **[verified]**; UBports reportedly integrates Halium 16 ports ([Phoronix](https://phoronix.com/news/Ubuntu-Touch-Toward-26.04), snippet only) **[unverified]**.

Each is the `halium_arm64` generic target ([repo](https://github.com/Halium/android_device_halium_halium_arm64)) with `zygote`, `surfaceflinger`, `system_server` and `bootanim` removed from `init.rc`. The device descriptor selects the image by `ro.vendor.api_level`; a device moves to Halium 16 the day it boots there, and 13/14 retire when unused. Vendor partitions are never redistributed; the installer reads them from the phone.

Two Android 15+ facts shape the glue. VNDK is deprecated for vendor API 202404+, so vendor partitions carry former-framework libraries in APEXes; upstream libhybris added "Android 15 and 16 support" and runtime-APEX library paths in March 2026 and AIDL-composer thread-pool initialisation in January 2026 ([VNDK](https://source.android.com/docs/core/architecture/vndk), [libhybris commits](https://github.com/libhybris/libhybris/commits/master)) **[verified]**. libgbinder ships API-level presets up to 36 (`aidl6`) ([gbinder_config.c](https://raw.githubusercontent.com/mer-hybris/libgbinder/master/src/gbinder_config.c)) **[verified]**.

### 1.3 How each hardware class is reached

- **Display and GPU**: no KMS driver; the compositor speaks hwcomposer (HWC2 HIDL on Android 11-12 vendors, AIDL `composer3` on 13+) through libhybris, and GLES/EGL/Vulkan come from the vendor ICDs. Vulkan on Halium under Wayland ran on the FuriLabs FLX1 in June 2026 and FuriLabs' libhybris carries the EGL sync/fence mapping through August 2026 ([linmob 23/2026](https://linmob.net/weekly-update-23-2026/), [FuriLabs libhybris](https://github.com/FuriLabs/libhybris/commits/forky)) **[verified]**.
- **Modem**: oFono + binder RIL plugin (`libgbinder-radio`) against the vendor `IRadio` HAL; IMS/VoLTE via `ofono-binder-plugin-ext-qti` (Qualcomm, UBports) and `-ext-mtk` (MediaTek, FuriLabs) ([UBports VoLTE](https://forums.ubports.com/post/82716), [FuriLabs repos](https://github.com/orgs/FuriLabs/repositories?type=source&sort=updated&page=2)) **[verified]**; MMS via `mmsd4ofono`.
- **Camera**: HAL3 through `cameraserver`, consumed by `droidmedia` + `gst-droid`; FuriLabs' `droidcam2v4l2` bridges it to `v4l2loopback` so portal-aware apps see a normal camera ([droidcam2v4l2](https://github.com/FuriLabs/droidcam2v4l2)) **[verified]**.
- **Audio**: vendor Audio HAL via `pulseaudio-modules-droid-modern` plus FuriLabs' `audio-manager` for call routing ([audio-manager](https://github.com/FuriLabs/audio-manager)) **[verified]**. No PipeWire droid module exists in 2026 (searched; none).
- **Sensors, NFC, Bluetooth, biometrics, GNSS**: `sensorfw` hybris plugin or FuriLabs' `gesture-sensors` presenting `net.hadess.SensorProxy` (Droidian's exact bridge **[unverified]**); `nfcd` + `nfcd-binder-plugin`; `bluebinder` feeding BlueZ; `biomd` for fingerprint; FuriLabs' `geoclue`; vibrator/lights/health over AIDL from a Kestrel daemon on libgbinder.
- **Kernel**: see 2.1.

### 1.4 Pre-flight test that removes guesswork

`kestrelctl preflight` boots Google's current GSI on a candidate device (DSU or fastboot) and records `ro.vendor.api_level`, GKI branch, `vendor_boot` module list and HAL manifest. GSI boots: the port is a kernel-and-adaptation job. GSI fails: not a Kestrel target. "Will it port?" becomes a 20-minute experiment.

## 2. Boot, kernel, init, updates

### 2.1 Kernel

Three regimes:

1. **GKI devices (Android 12+ launches, 5.10 to 6.12)**: SoC code lives in vendor modules behind a frozen KMI ([GKI](https://source.android.com/docs/core/architecture/kernel/generic-kernel-image)) **[verified]**. Kestrel starts from the *stock* GKI binary with its own ramdisk and rebuilds from the public Android Common Kernel branch (`android14-6.1`, `android15-6.6`, `android16-6.12`) only when a config is proven necessary, keeping vendor `.ko` blobs unchanged. Constraints: unsigned modules may only use allow-listed symbols, Google's own GKI modules must be rebuilt with our key because `CONFIG_MODULE_SIG_PROTECT` treats foreign-signed modules as unsigned ([kernel modules](https://source.android.com/docs/core/architecture/kernel/modules)) **[verified]**, and nothing may alter KMI-visible structs; so the fragment is `v4l2loopback`, `CONFIG_VT` off and little else.
2. **Pre-GKI devices (FP5 on 5.4, Volla/FLX1 on 5.10)**: classic Halium, vendor tree plus the Halium defconfig delta, per device.
3. **Mainline lane (section 10)**: Nura/Mobian generic kernels.

Boot image layout: on header-v4 devices Kestrel flashes only `init_boot` (our initramfs replaces Android's generic ramdisk; the bootloader prepends `vendor_boot`'s module ramdisk, so our init loads vendor modules from `modules.load` as Android first-stage init does) and `boot` only when the kernel is rebuilt; whether UBports' FP6 port uses this split is **[unverified]**. Header-v3 devices get a rebuilt `boot.img` as Halium always did.

### 2.2 Partitions and the Android container

The device's `system` partition is left alone (dual-boot stays possible). Everything Kestrel owns lives in `userdata` as LVM, which Droidian's initramfs already understands: it probes `userdata` honouring `androidboot.slot_suffix`, activates a volume group, unlocks LUKS via `unl0kr` and accepts a `datapart=` override ([initramfs script](https://raw.githubusercontent.com/droidian/initramfs-tools-halium/droidian/scripts/halium)) **[verified]**. VG `kestrel` holds `root_a`/`root_b` (EROFS + dm-verity), `halium_a`/`halium_b` (Android system image, ext4 + dm-verity), `state` (slot and boot-count, 16 MB) and `data` (LUKS2 with fscrypt v2 inside). The container is `lxc-android` (FuriLabs/Droidian config) under `android.service`; a generator parses the vendor `fstab` and mounts vendor partitions read-only from `/dev/block/by-name/*<slot>`. The HAL container gets `/dev/binderfs/{binder,hwbinder,vndbinder}`; Waydroid gets a separate binderfs instance so the two Android userspaces never share a context manager. SELinux starts permissive, as every Halium port does, with a Phase-3 goal of loading the vendor policy enforcing inside the container, since disabling it removes the vendor's own hardening ([app sandbox](https://source.android.com/docs/security/app-sandbox)).

### 2.3 Updates: image A/B with automatic rollback

Kestrel adopts Virtual A/B's semantics (snapshot-then-commit, success before rollback-index bump) ([Virtual A/B](https://source.android.com/docs/core/ota/virtual_ab)) without its machinery:

- **RAUC 1.15**: signed bundles, HTTP streaming, adaptive deltas, `raw` slots writing to the inactive `root_x`/`halium_x` LVs, and a `custom` bootloader backend that flips `state/slot` and resets the try counter ([RAUC changes](https://rauc.readthedocs.io/en/latest/changes.html)); the initramfs falls back after three failed boots. `systemd-sysupdate` is the alternative if a device moves to GPT sub-partitions under U-Boot (Duranium's layout).
- **Kernel/boot updates** go to the inactive bootloader slot, switched through the vendor `IBootControl` HAL over libgbinder (present on every A/B device because `update_engine` uses it), with `markBootSuccessful` after a verified boot; fallback is "flash both slots after a trial boot". Driving `IBootControl` from Linux is **[unverified]**.
- **Optional layers** (Waydroid, debug tools, Incus) ship as `systemd-sysext` images, as Nura's Duranium does for Waydroid ([Nura June 2026](https://nura.eco/blog/2026/07/06/pmOS-update-2026-06/)).

### 2.4 Verified boot and immutability

Default state is ORANGE. Root and Halium images are dm-verity protected and the initramfs verifies an ed25519-signed slot manifest (embedded key) for their root hashes, so tampered images fail even when the bootloader verifies nothing. On Pixels, which accept `avb_custom_key`, Phase 3 re-signs `boot`/`init_boot`/`vbmeta` (keeping OEM `system`/`vendor` descriptors) and relocks to YELLOW ([AVB boot flow](https://source.android.com/docs/security/features/verifiedboot/boot-flow)). Fairphone relocking is not offered: CalyxOS refuses to lock Fairphones over a bootloader bug that can brick, and iodé users report "device corrupt" on FP6 relock ([CalyxOS](https://calyxos.org/docs/guide/fairphone-relock/), [iodé](https://community.iode.tech/t/fp6-unable-to-lock-bootloader/8149)) **[verified]**. `/usr` is read-only EROFS, `/etc` factory-default symlinks plus an overlay, `/var` and `/home` in `data`.

## 3. Base system

- **Distro base: Debian 13 "trixie", glibc, systemd 257.** The whole Halium middleware (libhybris, libgbinder, pulseaudio-modules-droid, oFono binder plugins, droidmedia, gst-droid, lxc-android, initramfs-tools-halium) is maintained as Debian packages by Droidian and FuriLabs, and glibc is what libhybris was written for; Oniro's musl experience shows a second libc multiplies the friction. Ubuntu (UBports' base) was rejected because it re-introduces a Debian-to-Ubuntu rebase and because snaps need AppArmor, which GKI kernels lack (section 6).
- **Overlay repository**: `kestrel-halium`, an apt repo built by CI from FuriLabs' `forky` branches (wlroots, phoc, phosh, libhybris, ofono, audio-manager, batman, nfcd, bluebinder, biomd) on the trixie toolchain. Kestrel does not fork them; patches go to FuriLabs/Droidian/Halium first.
- **Image build**: `mkosi` produces the EROFS root and verity data (`debos`, Droidian's tool, is the fallback). apt exists only at build time; the device never runs it.
- **Init**: systemd, with `android.service` (LXC), `kestrel-androidd` (Go, cgo to libgbinder: health, vibrator, lights, power hints, bootctrl), `kestrel-powerd` (section 7), RAUC, greetd + `phrog`, Plymouth.
- **Languages**: Go for Kestrel daemons and tooling (the developer's strength; static binaries fit an initramfs), C only where wlroots/libhybris are touched, TypeScript for the shell. Rust buys nothing on this track: vendor kernels block Rust-in-kernel and the compositor base is C.
- **16 KB pages**: Pixel 8/9 offer 16 KB kernels as a developer option and Android 16 derives page size at init ([16 KB](https://source.android.com/docs/core/architecture/16kb-page-size/16kb)) **[verified]**; CI lints the whole image for 16 KB ELF alignment from day one. libhybris 16 KB readiness is **[unverified]**.

## 4. Graphics and compositor

Decision: **phoc on wlroots, FuriLabs branch**, the only compositor that provably runs on hwcomposer today and is commercially maintained. FuriLabs' `forky` wlroots is 0.17.4 with `hwcomposer-backend`, `android-renderer` and `vulkan-renderer` options and an in-tree `backend/hwcomposer` linking `libhybris-hwcomposerwindow` and `libhwc2`; their phoc is 0.44, pinned to wlroots 0.17 ([wlroots meson.build](https://raw.githubusercontent.com/FuriLabs/wlroots/forky/meson.build), [backend tree](https://github.com/FuriLabs/wlroots/tree/forky/backend), [phoc meson.build](https://raw.githubusercontent.com/FuriLabs/phoc/forky/meson.build)) **[verified]**. Upstream is at wlroots 0.20.2 and phoc 0.57/0.58, so the Halium lane runs three wlroots majors behind; Droidian's `feature/next/backport-0.18` (May 2026) is the only forward-port attempt ([droidian/wlroots branches](https://github.com/droidian/wlroots/branches/all)) **[verified]**.

Rejected on merit: Mir 1.8 + `mir-android-platform` works but is Qt5/Lomiri-bound, and Mir 2 still has no Android platform (UBports' Mir 2 proof of concept had Mir 1 driving the display) ([UBports Q&A 193](https://ubports.com/blog/ubports-news-1/ubuntu-touch-q-a-193-4003)); KWin removed its hwcomposer backend in 2020 ([KWin MR 551](https://invent.kde.org/plasma/kwin/-/merge_requests/551)); Smithay has none (searched); Qt Wayland Compositor has none and is GPLv3-or-commercial ([Qt docs](https://doc.qt.io/qt-6/qtwaylandcompositor-index.html)). The earlier Qt6/QML + Qt Wayland Compositor suggestion fails the "provably works on hwcomposer" test and would make Kestrel that combination's only user.

Kestrel's main graphics contribution, shared with FuriLabs and Droidian: a **forward-port of the hwcomposer backend to wlroots 0.20** as a maintained out-of-tree package, so phoc can track upstream within one release. Vulkan via libhybris then enables wlroots' Vulkan renderer and Zink for GL apps. On the mainline lane the same phoc uses its DRM backend over Mesa (Freedreno/Turnip; Mesa 26 covers Adreno 6xx-8xx) ([Mesa 26.0](https://docs.mesa3d.org/relnotes/26.0.0.html)); shell and apps never see the difference.

## 5. Shell, UI toolkit and the user-experience differentiator

Phases 1-2 ship **Phosh** as FuriLabs packages it (GTK4/libadwaita; their branch pairs with phoc 0.44 while upstream is at 0.57). It is the shell FuriOS and Droidian run on hwcomposer, and upstream brings a settings app, the Stevia OSK, `xdg-desktop-portal-phosh` and a six-week cadence ([Phosh news](https://phosh.mobi/posts/development-news-2026-09/)). Phase 3 introduces the differentiator.

**Kestrel Shell: a phone shell written in TypeScript, live-editable on the device.** It is built on GJS (GNOME Shell's runtime) with GTK4, `gtk4-layer-shell` and the Astal/AGS libraries, which already provide battery, network, Bluetooth, notification and tray bindings and a TypeScript scaffolding CLI ([AGS](https://github.com/aylur/ags)) **[verified, desktop-focused]**. It runs on phoc through the protocols Phosh uses (`wlr-layer-shell`, `ext-session-lock`, `xdg-activation`, `input-method-v2`/`text-input-v3`), so Phosh stays a drop-in fallback. Why this differentiator: every existing phone shell is C (Phosh) or QML (Lomiri and Sailfish on Qt5, Plasma Mobile on Qt6); none is hackable by the largest developer population there is, none hot-reloads, none runs identically nested on a laptop. Lock screen, quick settings, launcher and notification centre are TypeScript modules a user can edit on the phone and see reload without logging out; `kestrelctl shell dev` runs the same shell in a nested phoc window.

Secondary commitments: per-app privacy switches (microphone, camera, location, network) enforced at the portal and nftables layer; and Android apps shown as peers in launcher, notifications and share sheet.

Convergence is explicitly *not* a headline (Canonical sold it before the phone worked). It is an optional `incus` sysext for people who want LXD-style containers on their phone.

## 6. App model

- **Packaging: Flatpak only for third-party apps.** Flatpak 1.18.x + bubblewrap + `xdg-desktop-portal` 1.22 is what Droidian, Nura and Mobian use ([Flatpak 1.18.4](https://github.com/flatpak/flatpak/releases/tag/1.18.4)). On Halium devices GL/Vulkan inside the sandbox must come from libhybris; FuriLabs' `flatpak-hybris` exists for this (mechanism **[unverified]**) and Kestrel ships an `org.freedesktop.Platform.GL.hybris` extension in the same spirit.
- **Why not snap, click, OCI**: snap confinement needs AppArmor, absent from GKI kernels (enabling it means a rebuilt kernel on every device); click is a single-ecosystem format whose roughly 1,000 OpenStore apps Kestrel can still *run* through FuriLabs' `furios-lomiri-app-support` as an optional sysext; OCI is for build containers and the Incus sysext, not apps.
- **Permissions**: `kestrel-permd` (Go, D-Bus), modelled on Android runtime permissions and OpenHarmony's AccessToken. Caller identity is the Flatpak app-id (from `/.flatpak-info` via `GetConnectionCredentials`); permissions are `system_grant` or `user_grant` with one-time/session/always answers; user data is reachable only through portals (FileChooser, Camera, Location, ScreenCast), OpenHarmony's "pickers only" rule ([AccessToken](https://gitcode.com/openharmony/security_access_token/blob/master/README.md)).
- **Android apps**: Waydroid 1.6.3 (28 May 2026; Android 13 images default, initial Android 16 support) or FuriLabs' `andromeda` fork, in its own binderfs instance and cgroup, with camera via `droidcam2v4l2` rather than shared HAL access ([Waydroid tags](https://github.com/waydroid/waydroid/tags)) **[verified]**. The website says plainly that Play Integrity `MEETS_DEVICE_INTEGRITY` is impossible for a non-certified OS, so banking and some government apps will not work ([Play Integrity](https://developer.android.com/google/play/integrity/improvements)).
- **Web/PWA**: GNOME Web (WebKitGTK) "install as web app". **Flutter**: `flutter-elinux` Wayland embedder, apps only. **Native**: GTK4/libadwaita first-class; Qt6 via the Flatpak KDE runtime.

## 7. Telephony, audio, camera, sensors, power

- **Telephony**: oFono (FuriLabs fork) + binder plugin + `ext-qti`/`ext-mtk` IMS extensions, `mmsd4ofono`, GNOME Calls and Chatty on top (Chatty's oFono pairing in Droidian is **[unverified]**; FuriLabs' Python `telephony` daemon is the reference glue). VoLTE is the existential item: on UT it works on Qualcomm through the vendor IMS stack, with double-call and SMS regressions reported ([UBports VoLTE](https://forums.ubports.com/post/82716)) **[verified]**; FuriLabs ships it on MediaTek. Policy: no device is "supported" until VoLTE passes a 50-call test on two carriers. eSIM via `lpac` where the modem exposes an APDU path.
- **Audio**: PulseAudio + `pulseaudio-modules-droid-modern` + `audio-manager`, with a `callaudiod` shim for GNOME Calls. Phase 3 adds a **PipeWire SPA plugin for the Android Audio HAL** (`pipewire-droid`), which nobody has written: a strong contributor magnet.
- **Camera**: `droidmedia` + `gst-droid` + `droidcam2v4l2`, so the Camera portal and PipeWire see `/dev/videoN`; FuriLabs' `furios-camera` (Qt5) as the stopgap app ([furios-camera](https://github.com/FuriLabs/furios-camera)), a GTK4 Kestrel Camera later. Public expectation: basic HAL3 capture, no vendor HDR or night mode.
- **Sensors**: `sensorfw` hybris plugin or `gesture-sensors` presenting `net.hadess.SensorProxy`; rotation, ambient light and proximity are release blockers.
- **Power and standby**: Linux owns suspend. `kestrel-powerd` (Go) follows Android's `SystemSuspend`: it owns `/sys/power/wakeup_count`, hands wakelock handles over D-Bus to the shell, oFono and audio-manager, uses opportunistic autosleep and logs a Battery-Historian-style timeline ([Android power](https://source.android.com/docs/core/power/mgmt)). FuriLabs' `batman` is the tuning layer ([batman](https://github.com/FuriLabs/batman)) **[verified]**. Background apps are frozen with the cgroup v2 freezer between maintenance windows (Doze) and woken by exactly one push path, a UnifiedPush distributor; Doze without a sanctioned wake path breaks messaging. Evidence the target is reachable: UT on FP5 reports 24+ hours ([UT FP5](https://devices.ubuntu-touch.io/device/FP5/release/noble)). Release gate: 36 h idle with SIM and Wi-Fi on, measured by the HIL harness.

## 8. Security and privacy model

Honest threat model first. On the Halium lane the kernel is the vendor's GKI/LTS branch, patched only while Google and the OEM patch it; Landlock is ABI 2 on 6.1 and ABI 3 on 6.6 ([Landlock](https://docs.kernel.org/userspace-api/landlock.html)); the bootloader is unlocked on everything but Pixels; vendor HALs run as root in a permissive container. Kestrel does not claim GrapheneOS-class security. It claims *integrity and containment*:

1. dm-verity root and Halium images, signed slot manifests, signed RAUC bundles, reproducible builds with a published SBOM (CRA readiness for a future hardware partner).
2. All third-party code in Flatpak sandboxes with seccomp; no app sees `/dev/binder`, `/dev/video*` or the modem; portals or `kestrel-permd` mediate every grant.
3. User data on a LUKS2 LV with fscrypt v2 classes modelled on OpenHarmony's encryption levels: available at boot (system state), after first unlock (app data), evicted on lock (sensitive).
4. Vendor SELinux policy enforcing inside the container (Phase 3); Kestrel daemons under systemd hardening (`ProtectSystem=strict`, `DynamicUser=`, syscall filters).
5. Per-app privacy switches enforced out of process (portal denial, nftables cgroup match).
6. YELLOW verified boot on Pixels, with verified-boot key fingerprints published `attestation.json` style even though no Linux keystore can use them yet ([GrapheneOS attestation](https://grapheneos.org/articles/attestation-compatibility-guide)).
7. No telemetry and no account requirement.

## 9. Developer experience and build infrastructure

### 9.1 A device port is a generated repository

`kestrel-device-<codename>` holds `deviceinfo.toml` (validated by `kestrelctl lint`, which also renders the device page), `kernel/` (ACK branch + fragment, or a vendor tree reference), `adaptation/` (a Debian package: udev rules, `fstab` mapping, `gbinder.conf` API level, audio/sensor quirks, `batman` profile) and `tests/`. Most of it is *generated* by `kestrelctl device init` from the stock factory image (partition map, `ro.*` properties, vendor API level, `modules.load`, HAL manifest): GrapheneOS's `adevtool` idea applied to Halium, so no port depends on OEM-published device trees ([GrapheneOS releases](https://grapheneos.org/releases)). UBports' `halium-generic-adaptation-build-tools` is the closest existing tool and the reference for the boot-image step ([UBports porting docs](https://docs.ubports.com/porting/introduction/Intro.html)).

### 9.2 One CLI, one pipeline

`kestrelctl` (Go) wraps `preflight` (GSI boot test, 1.4), `kernel build` (ACK + fragment in a container), `halium build` (the generic system images, weekly from the Halium trees), `image build` (mkosi root, EROFS, verity, manifest), `flash` (fastboot to `init_boot`/`boot` plus the `userdata` LVM layout), `ota publish` (RAUC bundle to a static HTTPS server) and `shell dev` (nested phoc + hot-reloading shell). GitLab CI builds every device image nightly and on tag; its artifacts are the bundles users install.

### 9.3 Hardware-in-the-loop and emulator

From Phase 2, two phones per supported SoC family sit in a Nura-style phone harness with CI-tron; Nura's lesson is that nothing is "stable" without it ([Nura Feb 2026](https://nura.eco/blog/2026/02/26/pmOS-update-2026-02/)). Emulator: the Linux side (shell, apps, portals, updates) runs in QEMU `virt` with virtio-gpu on a mainline kernel, which is also how contributors without phones work (Oniro's lesson). For the Halium glue, a two-week experiment is booting a Halium system image on Cuttlefish's virtual vendor, since Cuttlefish hybrid devices already run a physical device's system image on virtual HALs ([Cuttlefish CHD](https://source.android.com/docs/devices/cuttlefish/create-chd)); nobody has done it and feasibility is **[unverified]**.

## 10. Per-device migration path to mainline

The contract layers let the hardware lane change underneath: Wayland + portals + D-Bus for apps and shell, plus small versioned Kestrel HAL interfaces (Varlink/D-Bus, OpenHarmony HDI-style major/minor rules) for telephony, audio routing, sensors, camera and power ([HDI](https://gitcode.com/openharmony/drivers_interface/blob/master/README.md)). A device profile is either `halium` or `mainline`:

| Function | `halium` profile | `mainline` profile |
|---|---|---|
| Kernel | GKI/vendor + vendor modules | Nura/Mobian generic kernel (`linux-postmarketos-qcom-*`, Debian 6.12) |
| Display/GPU | phoc hwcomposer backend, hybris GLES/Vulkan | phoc DRM backend, Mesa Turnip |
| Modem | oFono binder + IMS ext | ModemManager 1.24 + openimsd |
| Audio | PulseAudio droid + audio-manager | PipeWire + UCM + callaudiod (+ q6voiced) |
| Camera | gst-droid + droidcam2v4l2 | libcamera (qcom-camss) via PipeWire |
| Sensors | sensorfw hybris | iio-sensor-proxy / hexagonrpcd |

Promotion rule: a device moves to `mainline` when the Nura/Mobian kernel for its SoC reaches community tier and Kestrel's HIL suite passes on it (calls, SMS, data, VoLTE, camera, 36 h standby). First candidates: Fairphone 5 (Nura `qcom-qcs6490`, "mostly works"), later FP6 (SM7635; cameras and a VoLTE emergency call on edge in Aug 2026) ([Nura v26.06](https://nura.eco/blog/2026/06/21/v26.06-release/), [generic device packages](https://docs.nura.eco/pmaports/main/packaging/device-packages/generic-device-packages.html)). The author's OnePlus 6 is the mainline reference from day one: the same Debian root runs there on Mobian's 6.12 kernel, keeping the `mainline` profile honest while Halium devices carry the user base. Pixel 8/9/10 will likely stay `halium` indefinitely (no Tensor G3/G4 mainline device trees found).

## 11. Layer table

| Layer | Chosen tech | Why | Borrowed from |
|---|---|---|---|
| Bootloader | OEM ABL/fastboot, A/B slots; `avb_custom_key` on Pixel | Only option on retail phones; relock where OEM allows | Android (AVB), GrapheneOS |
| Kernel | Stock GKI (rebuilt from ACK only when needed) + vendor `.ko`; vendor tree for pre-GKI | Keeps vendor modules, LTS fixes flow from ACK | Android GKI, GrapheneOS, Halium |
| Initramfs | `initramfs-tools-halium` fork: LVM, LUKS/unl0kr, slot select, verity, boot counter | Already finds userdata/slots/LVM; small delta | Droidian/Halium |
| Driver layer | Stock vendor partitions in LXC under stripped Android init | Day-one hardware on 2023-2026 phones | Halium, Ubuntu Touch, Droidian/FuriOS |
| HAL IPC | libgbinder (API presets to 36), libhybris (FuriLabs/upstream) | Only maintained bionic/binder bridges | Sailfish/mer-hybris, Halium |
| Android system image | Generic `halium_arm64` for Halium 13/14/16, chosen by vendor API level | GSI model: one image per generation | Halium, Droidian, Google GSI |
| Base OS | Debian 13 trixie, glibc, systemd 257, read-only EROFS + dm-verity | Where all Halium middleware is packaged; immutable | Droidian/FuriOS, Nura Duranium |
| Image build and updates | mkosi images; signed RAUC A/B bundles on LVM, try-counter rollback, sysext for options | Virtual A/B semantics without AOSP machinery | Android Virtual A/B, Duranium, embedded Linux |
| Compositor | phoc on wlroots 0.17 (FuriLabs) with hwcomposer backend; forward-port to 0.20 | Only compositor proven on hwcomposer | Droidian/FuriOS, Phosh |
| Shell | Phosh now; Kestrel Shell (TypeScript/GJS/GTK4/layer-shell) later | Proven now; hackable differentiator later | Phosh; GNOME Shell/AGS |
| Apps | Flatpak + portals + GL.hybris extension; Waydroid; click via sysext | Audited sandbox, existing catalogues | Droidian, FuriOS, UT |
| Permissions | `kestrel-permd`: token identity, runtime grants, pickers-only | Coherent least privilege | Android, OpenHarmony |
| Telephony | oFono binder + qti/mtk IMS ext, mmsd4ofono, lpac | Only working VoLTE path on vendor modems | UT, FuriLabs, Sailfish |
| Audio | PulseAudio droid + audio-manager, later pipewire-droid | What ships today; PipeWire is the gap to fill | FuriLabs, mer-hybris |
| Camera | droidmedia/gst-droid + droidcam2v4l2 | HAL3 capture into V4L2 for portals | Sailfish, FuriLabs |
| Power | kestrel-powerd (wakeup_count, freezer, UnifiedPush) + batman | Android's model on Linux primitives | Android, FuriLabs, UT repowerd |
| Security | verity + signed manifests, Flatpak/seccomp, fscrypt v2 classes, vendor SELinux in container | Integrity and containment, honestly scoped | Android, OpenHarmony, Nura |
| Device model | Generated device repo, tiers with demotion, HIL CI | Treadmill survivability | postmarketOS/Nura, GrapheneOS adevtool |

## 12. What is borrowed and what is deliberately not

- **postmarketOS/Nura**: borrowed: validated declarative device descriptors, device tiers with automatic demotion, hardware-in-the-loop CI, Duranium's immutable layout and sysext trick, generic kernels for the mainline lane, firmware policy. Not borrowed: Alpine/musl (libhybris friction), the no-Android stance (no 2024-2026 phone found at Nura's community tier), the generative-AI contribution ban (Kestrel publishes its own policy early).
- **Ubuntu Touch/Lomiri**: borrowed: read-only root plus whole-image OTA as the outcome, click policy groups as the permission-prompt model, `deviceinfo`, click apps as a free catalogue, the VoLTE binder-extension approach. Not borrowed: Mir 1.8/`mir-android-platform` (single-user backend), Lomiri/Qt5 (migrating since 2021), the `system-image` server, Libertine.
- **Halium/Droidian/FuriOS**: borrowed almost wholesale: Halium trees and hybris-patches, libhybris/libgbinder, the LXC model, initramfs, generic image plus adaptation package, FuriLabs' telephony/audio/power/camera daemons with `forky` as upstream. Not borrowed: Debian sid as runtime base, apt on device, the two-years-per-device process (replaced by generated adaptations and GSI pre-flight).
- **OpenHarmony/HarmonyOS**: borrowed as patterns: HDI-style versioned HAL IDL, AccessToken-style identity and grant classes, pickers-only data access, encryption levels, driver-container thinking, a per-device conformance pack. Not borrowed: HDF/KAL, ArkTS/Cangjie, Rosen, DSoftBus (needs a trust fabric Kestrel lacks), locked bootloaders and vendor-signed sideloading.
- **Android**: borrowed: Treble/VINTF as compatibility database, GKI rebuild strategy, Virtual A/B and AVB semantics, isolation layering, SystemSuspend/Doze patterns, Cuttlefish for CI, adevtool-style factory-image mining. Not borrowed: the AOSP build graph, `update_engine`/APEX binaries, Play Integrity spoofing, the push monopoly (UnifiedPush instead).

## 13. Phased roadmap (1-3 people)

- **Phase 0, months 0-2**: `kestrelctl preflight`; rebuild FuriLabs `forky` middleware on trixie; boot a Kestrel root (Phosh/phoc, LVM, verity) on Fairphone 5 from the existing Halium knowledge; nested-phoc desktop loop.
- **Phase 1, months 2-6, the thesis milestone (M1)**: *one generic root image and the generic Halium images boot on two kernel regimes*, FP5 (pre-GKI 5.4, Halium 13) and FP6 (GKI 6.1, Halium 14), each with display, touch, Wi-Fi, data, SMS, CS calls and audio routing; a RAUC A/B update applied over the air and auto-rolled-back after a deliberately broken image; standby measured. First thing worth announcing; a Pixel 8/9 booting the same images would prove the thesis across three vendors.
- **Phase 2, months 6-12, daily driver on two devices**: camera, sensors, NFC, Bluetooth, fingerprint, Waydroid sysext, GL.hybris Flatpak extension, `kestrel-permd`, `kestrel-powerd` with the 36 h gate, VoLTE via `ext-qti`, two-phone HIL rig, Pixel 10 or OnePlus 13 on Halium 16, public images and a device completeness page. A second contributor (audio/telephony) is realistically needed here.
- **Phase 3, months 12-24, differentiation and hardening**: Kestrel Shell, wlroots 0.20 hwcomposer forward-port with FuriLabs/Droidian, `pipewire-droid`, vendor SELinux enforcing, YELLOW boot on Pixels, kernel A/B via `IBootControl`, Halium 13/14 retired as devices move to 16, legal entity and CRA-ready SBOM.
- **Phase 4, months 24-36, the mainline lane**: `mainline` profile for FP5 (Nura `qcom-qcs6490`) and OnePlus 6 (Mobian kernel) on the same root and shell; FP6 as it matures; hardware-partner talks only after two devices are daily-driveable.

Confidence: Phase 1 reuses working ports and is the most predictable; Phases 2-3 historically cost UBports about two years per flagship with a larger team, so the bet is that generated adaptations and GSI pre-flight halve that for GSI-clean devices.

## 14. Top risks and mitigations

1. **The hwcomposer backend stays frozen at wlroots 0.17** while Phosh/phoc move on. Mitigation: the 0.20 forward-port is a Phase-3 deliverable co-owned with FuriLabs and Droidian; phoc stays pinned to what the backend supports; never fork beyond their tree.
2. **Halium 16 does not stabilise**, or Android 15/16 vendor images (no VNDK, APEX libraries) break libhybris in new ways. Mitigation: keep Halium 13/14 for older vendors, send fixes to `hybris-patches`, treat Pixel 10/OnePlus 13 as stretch targets until Halium 16 has a second user.
3. **VoLTE never becomes generic**: IMS differs per modem vendor and `ext-qti` still regresses SMS. Mitigation: VoLTE gates the support tier; one Qualcomm and one MediaTek family; budgeted per-SoC binder tracing; openimsd on the mainline lane.
4. **A GKI rebuild breaks vendor modules** (KMI drift, `MODULE_SIG_PROTECT`). Mitigation: stock GKI binaries first, rebuild only on proven need, CI loads every vendor module on every kernel build.
5. **Bootloader policy closes** (OnePlus global following China, Pixel gating widening). Mitigation: Fairphone first, Volla/FuriLabs hardware as partners, Pixels as developer targets; no dependency on OEM device trees.
6. **Standby battery life** falls short because vendor power HALs assume Android's framework. Mitigation: `kestrel-powerd` + `batman`, vendor `IPower` hints over binder, a HIL-measured gate and published per-device numbers.
7. **Burnout and a bus factor of one.** Mitigation: generated ports, nightly CI, rollback that makes mistakes survivable, a non-profit home by Phase 3, an AI-assisted-contribution policy published early.
8. **Licensing**: vendor blobs come only from the user's device; phoc/GTK avoids the Qt Wayland Compositor and Slint licence questions.
9. **Play Integrity and government apps** exclude Kestrel permanently. Mitigation: say so on the first page; web fallbacks and attestation advocacy, never spoofing.
10. **Two Android userspaces fight over hardware.** Mitigation: separate binderfs instances, camera only through `droidcam2v4l2`, Waydroid as an optional sysext, off by default.

## 15. Open items marked unverified

`flatpak-hybris` internals; `IBootControl` from Linux; UBports' `init_boot`/`vendor_boot` handling on GKI; FP6 vendor API level; libhybris 16 KB readiness; Halium-on-Cuttlefish; Droidian's sensor bridge; UBports' Halium 16 device list. Each is a two-day Phase-0 spike; a negative result changes a phase estimate, not the architecture.
