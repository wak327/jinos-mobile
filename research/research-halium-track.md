# The Android-driver-reuse track: Halium, libhybris, Droidian, Ubuntu Touch 24.04, Sailfish OS, FuriOS

Research date: 2026-10-02. Everything about "current status" below was checked against 2025-2026 sources (URLs in section 7). Where I could not verify a claim it is marked **unverified**.

## 1. Architecture: how a glibc Linux userland reaches Android hardware

All five projects share one stack shape, inherited from Mer/Nemo (2012), Canonical's Ubuntu Touch (2013) and Halium (2017). From the bottom up:

**Kernel and boot.** The phone's *downstream Android kernel* is kept as-is (4.19 / 5.4 / 5.10 / 5.15 depending on launch year), rebuilt with a handful of defconfig changes: AppArmor, namespaces/cgroups for LXC, multiple binder devices (binderfs), and removal of Android-only restrictions. The Android ramdisk is replaced by a Halium initramfs (`hybris-boot` in Halium's AOSP tree; `initramfs-tools-halium` in Droidian, still updated September 2026) that locates the Linux rootfs (a loop image on the `userdata` partition, or a partition) and hands off to systemd. UBports currently says future releases need kernels of at least 5.10 or 5.14 (Q&A 185, March 2026). Devices launched with Android 12+ use Google's GKI; UBports' assessment is that GKI makes first boot harder but subsequent hardware enablement easier because kernels are more uniform.

**The Android container.** An LXC container named `android` boots the Android `init` from a *system image* (`/var/lib/lxc/android/android-rootfs.img` in Droidian) with the device's real `/vendor`, `/odm`, firmware, DSP and `persist` partitions mounted into it. Android init starts only hardware daemons: hwcomposer, audio HAL, cameraserver, sensors, radio (IRadio), GNSS, NFC, fingerprint/biometrics, lights, vibrator, keymaster. Zygote, SurfaceFlinger and system_server are disabled. libhybris' own README describes this as "stripped down Android" launched as a systemd service.

Two ways to get the system image:
- *Device-built (classic Halium)*: sync a trimmed AOSP tree for the matching Android version (`halium-9.0` … `halium-14.0` branches of `Halium/android` plus a device manifest in `Halium/halium-devices`), build `system.img` with the vendor repos. Needed for pre-Treble devices and still what UBports does per device.
- *Generic (Treble/GSI exploitation)*: since Android 8.1/9 vendor code lives on its own partition with a stable HIDL/AIDL + VNDK ABI toward `/system`. Droidian ships one generic Halium system image and states that on GSI-capable devices "often only kernel changes are necessary"; the per-device work becomes a Debian *adaptation package* (`adaptation-<device>`) with configs, scripts, udev rules and an apt repo. FuriLabs follows the same pattern (`adaptation-furiphone-krypton`, `adaptation-furiphone-radon`). UBports' porting docs likewise note that GSI "simplifies the task of building a viable port by removing much of the... task of getting the hardware-specific vendor blobs compiled". Android 16's official GSI requires a Treble device launched with Android 9+ and an unlocked bootloader; Google validates it on Pixel 6 through Pixel 9a.

**IPC bridge: binder.** Since Android 8 almost every HAL is *binderized* (HIDL, now AIDL). The host talks to them on `/dev/hwbinder`, `/dev/binder`, `/dev/vndbinder` through **libgbinder** (Jolla/mer-hybris, BSD-3-Clause): a GLib-event-loop binder client with runtime 32/64-bit detection and pluggable protocol variants `aidl`, `aidl2`, `aidl3`, `hidl`, selected per Android API level in `/etc/gbinder.conf`. Droidian adds `gbinder-python`. On top of libgbinder sit `libgrilio` + `ofono-ril-binder-plugin` (telephony over IRadio), `binder-nfc-plugin` for `nfcd`, and Droidian's `halium-wrappers` for Android utilities. Legacy passthrough HALs (`libhardware` `.so` modules) are instead loaded directly through libhybris; UBports' audio docs show the hybrid case where a binder-only audio HAL is reached by symlinking `audio.hidl_compat.default.so` and keeping the HAL process alive via `init.disabled.rc`.

**libhybris.** A bionic-ABI loader inside a glibc process: it ships its own ELF linker for bionic libraries, hooks libc symbols (the README is blunt about "patching Android to remove problematic TLS accesses in bionic"), and exposes wrappers for EGL/GLESv2, hwcomposer2, gralloc, camera, media, UI, and now Vulkan (UBports demoed a libhybris-Vulkan window under Wayland on a Fairphone in March 2026; FuriLabs lists Vulkan as a FuriOS feature). Licensing is a mix of Apache-2.0, BSD, LGPL-2.1, MIT, GPL-3.0 (tests). Upstream `libhybris/libhybris` has ~1,730 commits; FuriLabs' fork is at ~2,100 on a `forky` branch, i.e. the commercially maintained fork has pulled ahead. Important nuance from the Sailfish forum: a libhybris *package version* says nothing about the Android base; the same libhybris serves an Android 5 and an Android 14 port.

**Compositor integration (how pixels get out).** There is no KMS/DRM driver for the GPU; the compositor must speak hwcomposer through libhybris. Each project carries its own backend:
- Ubuntu Touch: **Mir** 1.8 with the out-of-tree **mir-android-platform** (`graphics-android2.so`, driver name `ubports:android2`) that UBports resurrected after upstream Mir dropped Android support. Lomiri is the Qt shell on top. Mir 2 is being brought up for 26.04; as of June 2026 it still showed "suspected heap corruption".
- Droidian / FuriOS: **Phosh + Phoc** (wlroots) with a libhybris hwcomposer backend maintained in Droidian's forks (exact backend details **unverified**).
- Sailfish OS: **Lipstick** (QtCompositor/Wayland) via `qt5-qpa-hwcomposer-plugin`.
- Waydroid's Android-app container renders through Mesa on mainline devices or through hybris gralloc on Halium devices.

**Middleware (largely Sailfish/Mer-hybris lineage, GPL/LGPL).** `pulseaudio-modules-droid` loads the vendor Audio HAL, exposes sinks/sources and does voice-call routing to earpiece/speaker/BT; `ofono` + binder plugin for calls/SMS/data; `sensorfw` with a hybris plugin; `nfcd`; `droidmedia` + `gst-droid` for camera (HAL3 via `cameraserver`) and hardware codecs through GStreamer (UBports replaced its old `qtubuntu-camera`/AAL path with gst-droid). UBports adds `hfd-service` (LEDs, haptics), `biometryd` (fingerprint), `repowerd` (suspend/power), and `deviceinfo`, a per-device key/value database (e.g. `PulseaudioModulesDroid_ExtraCardArgs`).

**OS layer differences.**
- *Ubuntu Touch 24.04*: Ubuntu 24.04 LTS base, read-only root with `/home`, `/var/log` etc. bind-mounted from `/userdata`; whole-image OTA through **system-image** (channels, delta tarballs, `system-image-cli`); apps as **click** packages (`manifest.json` + `apparmor.json` policy groups + `.desktop`, installed under `/opt/click.ubuntu.com/<app>/<ver>`, no external dependencies, confined by AppArmor; OpenStore as the store); **Libertine** LXC containers for desktop apps; **Waydroid** preinstalled since 20.04 for Halium 9+ devices. FSCRYPT v2 user-data encryption became non-experimental in 24.04-2.0.
- *Droidian / FuriOS*: plain Debian (Trixie) with apt, Flatpak and GNOME Software; FuriOS adds a daemon that installs and runs Ubuntu Touch click apps (March 2025) and its own Waydroid fork (`FuriLabs/andromeda`, GPL-3.0).
- *Sailfish OS*: RPM/zypper, Jolla Store plus OpenRepos, **Sailjail** (Firejail) app sandboxing, proprietary **Silica** UI toolkit and proprietary **AppSupport** (LXC-based since 3.0.1 in 2019, Android 13 in 5.0, Android 15 on the Jolla Phone 2026 in 5.2).

**Android app layer.** Waydroid runs a LineageOS-20-based Android 13 image in an LXC container using user/pid/uts/net/mount/ipc namespaces with direct hardware access; on a Halium device this means *two* Android userspaces (HAL container and app container) sharing binderfs and fighting over peripherals such as the camera (UBports documents exactly that conflict). Sailfish AppSupport is the same architecture, closed source, and sold per device.

## 2. What this track does well

1. **It is the only route to phones younger than ~3 years.** With mainline lagging 3-6 years, Halium ports exist for Fairphone 5 (97.4% feature coverage on UT's device page), Fairphone 4 (97.3%), Nothing Phone (1) (95.6%), Volla Quintus/Zinwa Q25, and all FuriLabs phones. Camera, fingerprint, NFC, calls and data all work on FP5.
2. **Clean containment boundary.** Everything bionic lives in one LXC container plus one loader library; the Linux side is an ordinary systemd distribution. Droidian proves the Linux half can literally be stock Debian.
3. **Treble made the Android half generic.** One generic Halium system image + a small adaptation package per device is a realistic one-developer workload for a GSI-capable device, as long as the kernel cooperates.
4. **Shared middleware across projects.** libgbinder, pulseaudio-modules-droid, ofono binder plugins, sensorfw, nfcd and gst-droid are reused by Sailfish, UBports, Droidian and FuriLabs; bugs fixed once benefit all. A new OS can join this pool instead of rewriting it.
5. **Ubuntu Touch's update model works for non-experts.** Read-only root + whole-image OTA + confined click apps has delivered nine years of OTAs across 111 devices with few bricks; 24.04-2.0 rolled Chromium 134, Widevine and FSCRYPT v2 to a decade-old fleet.
6. **Commercial validation.** FuriLabs has shipped four hardware products and "15 FuriOS releases" on this stack, with VoLTE/5G ENDC, Android apps, Vulkan and face unlock on sale for $499; Jolla shipped the Dimensity-7100 Jolla Phone (€649) in July 2026 with VoNR/Vo5G. The approach supports a product, not only a hobby.
7. **Cross-ecosystem app reuse is possible.** FuriOS running UT click apps, and UT running Waydroid, show that an OS can borrow another's catalogue cheaply.

## 3. What it does badly / lessons learned

1. **Per-device port cost is measured in years.** FP5 took about two years to reach the devel channel; the FP6 port (Halium 14) is explicitly at "the beginning of the journey" and expected to take as long. No Pixel 6/7/8/9 or OnePlus 9+ appears on the UT device list. A one-person team must plan for one or two devices, not a lineup.
2. **Halium trails Android by 2-3 versions.** UBports docs stop the mapping table at Halium 13 (Android 13) and describe it as still in development; the `halium-14.0` branch exists (April 2025) and is "working to some extent". Nothing targets Android 15/16 vendor partitions yet. The mitigating fact: what matters is the *vendor* API/VNDK level, not the shipped Android version (Fairphone 5 runs Android 15 on VNDK 30 = Android 11), so devices stay portable longer than their OS version suggests.
3. **libhybris is a permanent maintenance tax.** Every Android release moves bionic, the linker namespaces, gralloc and hwcomposer; Android 15 deprecated VNDK in favour of APEX-delivered libraries and removed `ro.vndk.version`, and the community is openly asking whether libhybris can be updated for APEX. Reviewers still see kernel processes stuck in D state on shipping FuriOS hardware.
4. **VoLTE/IMS is the unsolved problem.** Android keeps IMS inside vendor blobs (`vendor.qti.hardware.radio.ims`, `com.mediatek.ims`) with no standard interface. Sailfish's working QTI IMS ofono plugin is proprietary. UBports commissioned sysmocom (2021-22) to plan an open Doubango-based IMS stack and later pursued binder-level reverse engineering per vendor; in 2026 VoLTE works on a handful of UT devices (e.g. Redmi Note 9 Pro report, March 2025) but there is still no generic implementation. With 2G/3G shutdowns, a phone without VoLTE cannot make calls in many countries.
5. **Camera quality and features are capped.** HAL3 via `droidmedia`/`gst-droid` gives basic capture; HDR, multi-frame, night mode and multi-camera logic live in the vendor's Android camera app, which does not come along. FLX1s camera is described as comparable to a 2018 Samsung.
6. **Audio routing is fragile.** Voice-call paths depend on per-device mixer and HAL quirks (`rate=48000`, `hw_volume=false`, `use_legacy_stream_set_parameters=true`), binder-only HALs need shims, and Sailfish 5.2's routing rewrite for the new phone broke audio on older devices.
7. **Kernel security ends when the vendor stops.** You are on the vendor's downstream kernel forever; no KSPP hardening, no new fscrypt/LSM features unless the vendor had them. UT had to make FSCRYPT v2 device-conditional.
8. **Storage pressure is real.** Shipping Qt5 and Qt6 side by side made UT 24.04-2.0 too large for the Pixel 3a, which was dropped from the update.
9. **Carrying a compositor backend nobody upstream wants.** Mir dropped Android; UBports has maintained mir-android-platform alone since, and the Mir 1 -> Mir 2 migration has taken several years. Phosh/Phoc and Lipstick carry equivalent hwcomposer backends. Whatever compositor you pick, you own this code.
10. **Two Android containers on one phone.** Waydroid beside the Halium container doubles memory, drains battery, and conflicts on camera/sensors; banking apps fail Play Integrity anyway.
11. **Proprietary core is a dead end (Sailfish).** Silica and AppSupport being closed kept the community from carrying the OS; Jolla has been restructured, the official blog was archived in July 2026, and the 2026 phone ships EU-only in small batches. Open-sourcing started only in September 2025.
12. **Toolkit debt.** Lomiri is still Qt5 (Qt6 arrived in 24.04-2.0 only for the browser); Sailfish is on an old Qt5 with Qt6 still "pending". Lesson: do not start a new OS on a toolkit already in maintenance mode.

## 4. Status as of 2026-10-02

- **Halium**: `Halium/halium-devices` branches: `halium-14.0` (last commit April 2025), `halium-13.0` (October 2024), `halium-9.0` (February 2024); older branches dormant. docs.halium.org still documents 9-12 as supported and Android 13 as in development. No Android 15/16 target. Project is alive but driven by UBports and Droidian/FuriLabs people rather than as an independent effort.
- **Ubuntu Touch**: 24.04-2.0 released 25 July / 2 August 2026 with Chromium-134 Morph browser on Qt6, Qt5+Qt6 coexistence, Widevine, FSCRYPT v2, notch/rounded-corner support, screenshot editor; 24.04-1.4 maintenance in parallel. 111 devices listed; promoted: FP5, FP4, OnePlus Nord N100, Volla Phone 22/Quintus/Tablet. Core team described in June 2026 as "growing with significant funding and 10+ contributors". Roadmap: rebase on Ubuntu 26.04, Mir 1 -> Mir 2, new calendar/contacts backends. FP6 port on Halium 14 just started; Pixel 8/9 ports: none found (**unverified** whether any private effort exists).
- **Droidian**: alive; GitHub org shows 187 repos with Phosh/Mutter/GNOME Shell forks and `initramfs-tools-halium` updated August-September 2026; homepage branded "Droidian 2026"; base is Debian Trixie per third-party summaries. Device list page did not render for me (**unverified** current device count).
- **FuriOS / FuriLabs**: FLX1s+ (Dimensity 900, 8 GB, $499) in stock since June 2026, FLX1s shipped January 2026; FLX1 (Dimensity 7050) is the original. 195 GitHub repos including forks of libhybris, ofono, phosh, Waydroid (`andromeda`), plus `telephony`, `audio-manager`, `batman`. Claims VoLTE/5G ENDC, Vulkan, face unlock, Android apps; independent January 2026 review found camera and Bluetooth fine, 5 GHz Wi-Fi broken, no USB-C display out on FLX1s. The commercial fork is now the most active libhybris lineage.
- **Sailfish OS**: 5.0 "Tampella" (Feb 2025, AppSupport Android 13, microG 0.3.6); 5.0.0.76 (Mar 2026); 5.1 "Pispala" (16 Jun 2026, Bluetooth passthrough to Android apps); 5.2 "Finlayson" (20 Jul 2026, Jolla Phone only, AppSupport Android 15, Gecko ESR 115, VoNR). Jolla Phone 2026: Dimensity 7100, 8/12 GB, €649, shipping to Europe only since 8 July 2026. Licensing: Silica, AppSupport, EAS remain proprietary; partial open-sourcing since September 2025 (scope **unverified**). Jolla blog archived July 2026.
- **Waydroid**: Android 13 / LineageOS 20 base; latest release reported as 1.6.3 (May 2026) and packaged in Debian/Ubuntu universe (**reported, not independently verified**).
- **Android platform constraints**: Android 15 deprecated VNDK (vendor libs now in vendor/product partitions, VNDK APEXes kept only for vendor images <= 14); Android 16 GSI (build of 3 June 2025) still supports any Treble device launched on Android 9+. Expect vendor API level, not Android version, to be the compatibility axis going forward.

## 5. Borrowable ideas for a new OS

Concrete components (licence in brackets) and patterns worth adopting rather than reinventing:

1. **Keep the Halium contract**: downstream kernel + LXC Android HAL container + libhybris. Reuse `initramfs-tools-halium` (Droidian, GPL) and `halium-wrappers`; reuse Halium's `test_hwcomposer`, `test_egl`, `test_glesv2` bring-up tools. A port becomes "kernel defconfig + adaptation package", exactly the Droidian/FuriLabs model.
2. **libgbinder** [BSD-3] as the only HAL IPC layer; its `/etc/gbinder.d/*.conf` API-level presets are the right abstraction for Android 13-16 vendor partitions. A Go developer can write a pure-Go binder client using libgbinder as the reference (binder is an ioctl protocol on `/dev/*binder`), but should start by linking libgbinder via cgo.
3. **Track FuriLabs' libhybris fork** rather than upstream; it has Vulkan and the newest fixes and a company paying for it. Do not fork it yourself.
4. **Generic system image + adaptation package** (Droidian). Encode per-device facts in a `deviceinfo`-style key/value DB (UBports) consumed by audio, display and sensors services.
5. **Telephony**: `ofono` + `ofono-ril-binder-plugin`/`libgrilio` [GPL-2] today; budget for an IMS plugin per modem vendor and prefer one modem family (MediaTek is what FuriLabs and Jolla chose; UT's working VoLTE reports are Qualcomm Redmi/Pixel-3a class).
6. **Audio**: `pulseaudio-modules-droid` [LGPL-2.1]. There is no mature PipeWire equivalent I could verify; a `pipewire-droid` SPA plugin would be a genuinely new contribution and a good contributor magnet.
7. **Sensors/NFC/media**: `sensorfw` hybris plugin, `nfcd` + `binder-nfc-plugin`, `droidmedia` + `gst-droid` [LGPL/Apache]. Expose them over D-Bus/Varlink so the UI toolkit is replaceable.
8. **Compositor**: whichever you choose (wlroots-based, Mir 2, Qt Wayland Compositor, Smithay) you need a libhybris hwcomposer2 *and now Vulkan* backend. Existing ones: mir-android-platform (UBports), Droidian's wlroots/Phoc backend, Sailfish's qt5-qpa-hwcomposer. Evaluate by backend maturity, not toolkit preference. Vulkan via libhybris with Wayland is now demonstrated and is the forward-looking path (Zink for GL on top).
9. **OTA and filesystem**: copy UT's *outcome* (read-only root, atomic whole-image updates, `/userdata` overlay, channels) but implement it with 2026 tools: A/B root images with `systemd-sysupdate`, dm-verity, `systemd-repart`, UKIs, and FSCRYPT v2 for user data; the UT `system-image` server protocol itself is old Canonical code.
10. **App confinement**: UT's click `policy_groups` show the UX for declarative permissions; implement with Flatpak + portals (or snaps, given the author's background) rather than hand-written AppArmor JSON. Keep the "no external dependencies, bundle everything" rule for store apps.
11. **Android apps**: Waydroid [GPL-3] or FuriLabs' `andromeda` fork; expose a store client like FuriOS does. Plan binderfs device allocation so the HAL container and the app container never collide.
12. **Cross-ecosystem compatibility daemon** (FuriOS running UT click apps): running OpenStore's ~1,000 Qt/QML click apps and Flathub on day one is cheaper than courting app developers.
13. **Device selection policy**: Fairphone-class devices (unlockable, kernel source published, vendor upstreams patches), launched on Android 13/14 vendor partitions with 5.10+/5.15 GKI kernels, 256 GB storage. FuriLabs' and Jolla's choice of MediaTek mid-range SoCs with published kernels is a template for a hardware partner.

## 6. Pitfalls to avoid

- Do not target devices whose vendor partition is Android 15/16 until a Halium 15 exists; check `ro.vendor.api_level`/VNDK level, kernel source availability and bootloader policy before buying (OnePlus is tightening unlocking; Pixel kernel source is now gated).
- Do not write your own bionic loader, binder stack or hwcomposer backend; every project that did now carries it alone.
- Do not build the shell on a toolkit in maintenance mode (Qt5) or on proprietary UI components (Silica). Both UT and Sailfish are paying for it in 2026.
- Do not postpone VoLTE/IMS; without it the phone cannot call in 2G/3G-sunset markets. Choose the modem vendor first, then the device.
- Do not assume camera parity with Android; set expectations at "basic HAL3 capture".
- Budget rootfs size from day one; dual toolkits or large runtimes cost you devices (Pixel 3a was dropped for size).
- Avoid running two Android containers unless the memory budget and binder device plan exist.
- Do not redistribute vendor partitions or GSI+vendor combos; follow UT's model where the installer pulls blobs from the device.
- Assume ~2 years per flagship-class port with one developer; pick one primary device and one secondary, both GSI-capable.
- Do not treat libhybris version numbers as Android compatibility indicators; compatibility is decided by the vendor API level and the matching Halium branch.
- Plan for vendor-kernel EOL: no mainline, no security patches; mitigate with strict userland sandboxing and verified boot rather than pretending the kernel is maintained.

## 7. Sources

- UBports, "How Ubuntu Touch works": https://ubports.com/blog/ubports-news-1/how-ubuntu-touch-works-3896
- UBports, "Ubuntu Touch 24.04-1.3 release and updates on 24.04-2.0": https://ubports.com/blog/ubports-news-1/ubuntu-touch-24-04-1-3-release-and-updates-on-ubuntu-touch-24-04-2-0-3996
- Phoronix, "Ubuntu Touch 24.04-2.0 Released" (25 Jul 2026): https://phoronix.com/news/Ubuntu-Touch-24.04-2.0-Release
- Desdelinux, "Ubuntu Touch 24.04-2.0: Chromium 134, Widevine, FSCrypt v2": https://blog.desdelinux.net/en/ubuntu-touch-04-24-2-0-news-chromium-134-fscrypt/
- UBports Q&A 192 (13 Jun 2026): https://ubports.com/blog/ubports-news-1/ubuntu-touch-q-a-192-4002
- UBports Q&A 185 (7 Mar 2026): https://ubports.com/blog/ubports-news-1/ubuntu-touch-q-a-185-3992
- UBports porting docs, Halium/Android mapping and GSI: https://docs.ubports.com/en/latest/porting/introduction/Intro.html
- UBports porting docs, audio (pulseaudio-modules-droid, binder HAL workaround): https://docs.ubports.com/en/latest/porting/configure_test_fix/Sound.html
- UBports docs, click packages: https://docs.ubports.com/en/latest/appdev/platform/click.html
- UBports docs, Waydroid on Ubuntu Touch: https://docs.ubports.com/en/latest/userguide/dailyuse/waydroid.html
- UBports device list (111 devices, percentages): https://devices.ubuntu-touch.io/
- UBports forum, Fairphone 6 port (Halium 14, two-year expectation): https://forums.ubports.com/post/94806
- UBports forum, Halium 14 / GKI / VNDK 30 on FP5 / APEX question: https://forums.ubports.com/post/89132
- UBports forum, VoLTE status thread: https://forums.ubports.com/topic/8748/status-of-volte-voice-over-lte-4g-implementation?page=2 and https://forums.ubports.com/post/77108
- UBports blog, "First steps in VoLTE support" (sysmocom plan): https://ubports.com/blog/1/post/first-steps-in-volte-support-for-ubuntu-touch-3768
- Canonical Mir docs, platform support (UBports Android platform): https://canonical.com/mir/docs/stable/explanation/platform-support/
- Halium docs: https://docs.halium.org/en/latest/ and graphics debug page https://docs.halium.org/en/latest/porting/debug-build/graphics.html
- Halium device manifests, branches (halium-14.0 Apr 2025): https://github.com/Halium/halium-devices/branches/all
- Halium related projects: https://github.com/Halium/docs/blob/master/project/Related-projects.rst
- libhybris upstream: https://github.com/libhybris/libhybris ; FuriLabs fork: https://github.com/FuriLabs/libhybris
- libgbinder (mer-hybris): https://github.com/mer-hybris/libgbinder ; Waydroid fork: https://github.com/waydroid/libgbinder
- ofono-ril-binder-plugin recipe: https://layers.openembedded.org/layerindex/recipe/193443
- Droidian FAQ: https://docs.droidian.org/faq ; porting guide: https://docs.droidian.org/porting-guide ; image creation: https://docs.droidian.org/porting-guide/image-creation/
- Droidian GitHub org and halium repos: https://github.com/droidian and https://github.com/orgs/droidian/repositories?q=halium
- Droidian homepage: https://droidian.org/
- FuriLabs homepage (FLX1s+ specs, price, features): https://furilabs.com/
- FuriLabs GitHub org: https://github.com/FuriLabs ; Waydroid fork: https://github.com/FuriLabs/waydroid (redirects to andromeda); ofono fork: https://github.com/FuriLabs/ofono
- Liliputing, FLX1s: https://liliputing.com/flx1s-is-a-new-linux-phone-thats-mostly-a-downgrade-from-the-flx1/
- Russell Coker, FLX1s review (Jan 2026): https://etbe.coker.com.au/2026/01/19/furilabs-flx1s/
- LinMob weekly 13/2025 (FuriOS runs UT apps; miatoll VoLTE): https://linmob.net/weekly-update-13-2025/
- Waydroid docs: https://docs.waydro.id/
- Sailfish OS 5.0.0.76 release notes: https://forum.sailfishos.org/t/release-notes-tampella-5-0-0-76/28285
- Sailfish OS 5.2.0.15 release notes (Jolla Phone only): https://forum.sailfishos.org/t/release-notes-finlayson-5-2-0-15-jolla-phone-only/30793
- Jolla blog, "Sailfish OS 5.0 Tampella is here!": https://blog.jolla.com/?p=5009 ; blog index (archived July 2026): https://blog.jolla.com/
- Sailfish forum, licensing and Jolla Phone 2026: https://forum.sailfishos.org/t/on-sailfish-os-licensing-and-the-jolla-phone-2026/27497
- Sailfish forum, Jolla C2 Halium version (libhybris version vs Android base): https://forum.sailfishos.org/t/jolla-c2-halium-version/25116?page=2
- Sailfish forum, AppSupport in LXC since 3.0.1: https://forum.sailfishos.org/t/alien-dalvik-on-older-devices-has-the-same-naming-as-android-app-support-on-newer-devices/8930
- Android Authority, Jolla Phone 2026 hands-on: https://www.androidauthority.com/jolla-phone-2026-hands-on-3646591/
- Wikipedia, Sailfish OS (version history 5.0/5.1/5.2): https://en.wikipedia.org/wiki/Sailfish_OS
- AOSP, VNDK overview and deprecation in Android 15: https://source.android.com/docs/core/architecture/vndk
- Android 16 GSI release notes: https://developer.android.com/about/versions/16/gsi-release-notes
- AsteroidOS wiki, graphic stack (qt5-qpa-hwcomposer via libhybris): https://wiki.asteroidos.org/index.php/Graphic_Stack
- UBports forum, gst-droid replacing qtubuntu-camera: https://forums.ubports.com/post/23764
