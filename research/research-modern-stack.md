# The modern Linux mobile stack in 2026: maturity verdicts per component

Research date: 2026-10-02. Verdict scale: **production-ready** (shipping to users in at least one mobile distro, actively maintained), **promising** (real code, real users, but gaps a one-person team would have to fill), **avoid for a small team** (would require forking, maintaining a backend, or betting on something stalled).

A note on the two hardware paths, because almost every verdict below splits on it:

- **Path A, mainline kernel + DRM/KMS + Mesa** (postmarketOS/Nura, Mobian, Mobile NixOS). Everything "modern" in this report works here.
- **Path B, Android vendor kernel + libhybris/Halium** (Ubuntu Touch, Droidian/FuriOS). GPU, camera, modem and audio are reached through Android HALs; most modern userspace works unchanged, but the compositor needs a hwcomposer backend, the kernel is 5.10/5.15/6.1/6.6-android with no Rust and often an old Landlock/BPF, and Mesa is irrelevant to the display path.

Also a naming note: **postmarketOS rebranded to "Nura" on 2026-09-27** (domain nura.eco; the Nura Project ASBL, a Belgian non-profit, was announced 2026-09-28). Sources below use whichever name the page carries.

---

## 1. Architecture (layers, key components, how hardware is reached)

A 2026 Linux phone stack, bottom to top:

1. **Boot**: Android bootloader (ABL) → either a boot.img with kernel+initramfs (classic pmOS), or **U-Boot as a second-stage UEFI provider** → systemd-boot → **UKI** (Nura's Duranium and the new "main category" rules require UEFI boot). Duranium installs into the Android `userdata` partition via GPT sub-partitions exposed with U-Boot's `blkmap`, avoiding repartitioning.
2. **Kernel**: mainline (Path A) with generic per-arch kernels (`linux-postmarketos-{mainline,stable,lts}`, Feb 2026) or an android-5.10…6.6 vendor kernel (Path B). Rust is a first-class kernel language since Dec 2025, but only matters on Path A.
3. **Hardware access**: Path A uses DRM/KMS + Mesa (Freedreno/Turnip, Panfrost/PanVK, PowerVR), V4L2/libcamera, ALSA + Qualcomm q6 audio drivers, ModemManager over QRTR/QMI (with openimsd for IMS). Path B uses libhybris to dlopen bionic blobs: hwcomposer2 for display, Android EGL/GLES for GPU, droidmedia for camera/codecs, audioflinger/pulse-droid for audio, oFono + binder RIL plugin for the modem.
4. **System layer**: systemd (261/262), systemd-sysupdate for A/B OTA, systemd-repart, systemd-homed/fscrypt for user data, PipeWire + WirePlumber for audio and camera, bluez, NetworkManager, iio-sensor-proxy, feedbackd, callaudiod.
5. **Display server**: a Wayland compositor (phoc/wlroots, cosmic-comp/Smithay, KWin, Mir). Shell and compositor are usually separate processes (Phosh/phoc, Lomiri/lomiri-system-compositor) or one (KWin+plasmashell, cosmic-comp+cosmic-panel).
6. **Apps**: Flatpak + bubblewrap + xdg-desktop-portal; GTK4/libadwaita or Qt6/QML; optional Waydroid LXC for Android apps.

---

## 2. Components and verdicts

### 2.1 Wayland compositors and libraries

| Component | Latest (date) | hwcomposer/libhybris backend? | Verdict |
|---|---|---|---|
| **Smithay / cosmic-comp** | smithay crate 0.7.0 (2025-06-24, MIT); COSMIC Epoch 1.8 (2026-09-09) added touch input to cosmic-comp; on-screen keyboard still pending | **No.** Only an abandoned fork attempted anvil-on-Android. Backends are DRM/KMS (udev), winit, X11, headless. | **Promising (Path A only).** Rust, MIT, 13 downstream compositors incl. the mobile-focused **Catacomb** (GPL-3, moved to SourceHut 2026-05). You would write the mobile shell yourself. |
| **wlroots / phoc** | wlroots 0.20.2 (Arch 2026-07-10); phoc 0.57 moved to wlroots 0.20.2 (Aug 2026), 0.58~alpha1 (2026-09-21); Phosh 0.55 ships in Nura v26.06 | **Yes, out of tree.** Droidian's `droidian/wlroots` carries the hwcomposer backend; Droidian 101 (Sept 2025) ships wlroots **0.17.4**, and the `feature/next/backport-0.18` branch was last touched 2026-05-07. Upstream is at 0.20, so the Halium path runs 2–3 major versions behind. | **Production-ready on Path A**; on Path B it works (FuriOS FLX1/FLX1s ship it) but you inherit a perpetual fork. |
| **Mir / Lomiri** | Mir 2.30.0 (GitHub tag "Sep 24", 2026); Rust is now a build requirement (Rust evdev input platform). Ubuntu Touch 24.04-2.0 released 2026-07-24 (Chromium 134 browser, fscrypt v2 encryption out of experimental, 20 devices) but **still on Mir 1.8 + Qt 5**; Lomiri's Mir 2 move (via "Miroil") and Qt 6 migration are planned for H2 2026. | **Yes:** `mir-android-platform` (UBports GitLab, GPLv3, 99 commits) via libhybris. It is the only hwcomposer backend in production for years. | **Production-ready on Path B, but legacy.** The codebase is large, Qt5-bound, and the Mir 2/Qt 6 migration has been "in progress" since 2021. Do not fork; consume as a reference. |
| **KWin / Plasma Mobile** | Plasma Mobile 6.6.5 in Nura v26.06 | **No.** hwcomposer backend removed in 2020 (KWin MR 551); Plasma Mobile dropped Halium. Issue plasma-mobile#275 proposes reviving it out of tree; no owner. | **Production-ready on Path A; avoid on Path B.** |
| **Mutter / GNOME Shell mobile** | GNOME 50 desktop, but the mobile variant in Nura v26.06 is still `48.mobile.0` (a downstream fork) | **No.** | **Avoid as a base.** Mobile shell is an unmerged fork lagging two releases. |

Takeaway: there is **no modern (Rust or wlroots-0.20) compositor with a maintained hwcomposer backend**. If you target Path B, you either adopt Droidian's wlroots fork or write a hwcomposer backend for Smithay (roughly: an `Output` backend over libhybris `hwcomposer2` + EGL via `hybris-egl`). Budget months, not weeks.

### 2.2 UI toolkits for shell and apps

| Toolkit | Latest | Mobile/Wayland reality | Licence | Verdict |
|---|---|---|---|---|
| **GTK4 + libadwaita** | libadwaita 1.9.2 (2026-06), 1.10 alpha (2026-07); GTK 4.21.x | Adaptive widgets proven by Phosh/Mobian/Nura apps for 5+ years; OSK via phosh-osk-stub/stevia | LGPL-2.1+ | **Production-ready** for apps and a Phosh-style shell. |
| **Qt 6 / QML** | Qt 6.11 | Mature touch/QML; Qt Virtual Keyboard; Lomiri still Qt5 | Qt Quick LGPLv3; **Qt Wayland Compositor is GPLv3 or commercial only** (Qt docs) | **Production-ready**, but the compositor-module licence forecloses a proprietary or permissively licensed compositor; and you would be the first to ship a Qt6 phone shell. |
| **Slint** | 1.18.1 (2026-09-21); Rust/C++/JS/Python | Wayland via winit/Skia or FemtoVG; <300 KiB runtime; LSP + live preview | GPLv3, or royalty-free for "desktop, mobile and web" with attribution (**embedded excluded**), or commercial | **Promising.** Clarify with Slint whether a phone OS shell counts as "mobile" or "embedded"; GPLv3 is always available. |
| **Iced / libcosmic** | 0.14.0 (2025-12-07): IME, headless tests, hot reload, time-travel debugging | Powers COSMIC; touch arrives via cosmic-comp 1.8; accessibility and OSK integration immature | MIT | **Promising** if you go all-Rust with Smithay; expect to write mobile widgets. |
| **Flutter on Linux** | Official GTK embedder is **X11-only**; the Wayland issue had "still chipping away" in Jan 2026 and lost its assignee in May 2026. Sony's flutter-elinux offers Wayland/DRM embedders; Denial WM (Aug 2026) embeds Flutter in a compositor | Apps fine via flutter-elinux; shell integration is bespoke | BSD-3 | **Avoid for the shell; acceptable for apps.** |
| **Web / Tauri** | Tauri 2 on Linux = WebKitGTK only; Verso/Servo runtime archived 2025-10-08 | No viable Rust webview; WebKitGTK is heavy on phones | MIT/Apache | **Avoid for shell**; OK for individual apps. |

### 2.3 Rust in the kernel and in system userspace

- **Kernel:** at the 2025 Maintainers Summit Rust was declared no longer experimental; Miguel Ojeda's "conclude the Rust experiment" patch landed Dec 2025. Android 16 devices on 6.12 ship a Rust `ashmem`; Nova (NVIDIA) and **Tyr (Arm Mali CSF)** drivers kept growing through Linux 7.1–7.3; Dave Airlie said DRM is "about a year away" from requiring Rust for new drivers. **Verdict: production-ready for new drivers on Path A.** On Path B, android-5.10/5.15/6.1 kernels have no usable Rust toolchain support, so it is irrelevant.
- **Userspace:** Ubuntu made sudo-rs and uutils coreutils default in 25.10; 26.04 LTS kept GNU `cp/mv/rm` over TOCTOU findings (Zellic audit: 113 issues, most fixed); 26.10 completes the switch. **Verdict: production-ready** (and a safe default for a Go/Rust-comfortable developer).

### 2.4 Audio and camera

- **PipeWire + WirePlumber:** PipeWire 1.6 (2026-02-19), 1.6.9 by Sept 2026; LDAC decoder, 128 channels, HDR metadata. Mobile call routing uses **callaudiod**; Nura funded callaudiod/WirePlumber work in 2025 and in May 2026 financed **q6voice(d)** through Linaro: a kernel driver plus daemon to route voice-call audio through the Qualcomm audio DSP on MSM8916/SDM845/SDM670/MSM8953. Devices from 2022+ (SM8350 and newer) use **AudioReach** and are *not* covered. **Verdict: PipeWire production-ready; voice-call audio on recent Qualcomm mainline is a gap.**
- **libcamera:** 0.7.2 (Arch 2026-08-31; Nura's July 2026 update headlines it); software ISP with GPU acceleration demoed at ELCE 2025; PipeWire's libcamera SPA plugin lets any portal-aware app see phone cameras. **Verdict: promising on Path A** (each sensor/ISP needs tuning work). On Path B the camera goes through Android HAL + droidmedia, not libcamera.

### 2.5 Telephony: ModemManager vs oFono, VoLTE/IMS

- **ModemManager** 1.24.x (Arch 2025-08-05) with the `qcom-soc` plugin handles integrated Qualcomm modems over **QRTR/QMI** (SDM845, QCS6490, etc.). **oFono** survives mainly in Ubuntu Touch and Sailfish via a binder/RIL plugin against the Android telephony stack on Path B.
- **VoLTE on mainline:** **openimsd** (NGI0-funded since June 2024) is a daemon beside ModemManager that brings up the Qualcomm IMS stack over QMI; demos on Pixel 3a and OnePlus 6T; in May 2026 it upstreamed ringback-tone support into libqmi, ModemManager and GNOME Calls, and released a QCOM baseband profile manager (Feb 2026). **81voltd** (Debian 1.2.0) is a similar IMS-data helper. Nothing is carrier-tested at scale.
- **VoLTE on Halium:** works today in Ubuntu Touch because the Android IMS stack does the work (24.04-1.2 fixed VoLTE/mobile-data conflicts).
- **Verdict:** ModemManager production-ready for data/SMS/CS calls on Path A; **VoLTE on mainline is promising, not production**. Since carriers are shutting 2G/3G, a Path-A phone without openimsd is a data-only device in many countries.

### 2.6 Immutable/atomic OS tooling and A/B on phones

- **systemd 262** (2026-06-19): sysupdate gains a persistent installed-files DB, `cleanup`, and a Varlink API; sysext/confext merge from the initrd; repart supports LUKS2-inside-dm-verity DDIs and `BlockDeviceReplace=` for atomic partition migration; homed defaults to **fscrypt v2**; musl ≥1.2.6 is supported upstream (Nura runs systemd 261 on Alpine 3.24 in v26.06).
- **Duranium** (Nura, introduced 2026-03-17): EROFS `/usr` verified by **dm-verity** with the root hash in the **UKI**, two 5 GB A/B slots, systemd-sysupdate with automatic rollback, mandatory LUKS2 for mutable data, `/etc` factory-default symlinks, Flatpak + "coldbrew" for apps, sysext planned, Secure/verified boot pending. Status: "work in progress, seeking testers".
- **GNOME OS** chose systemd-sysupdate over bootc (no package manager, pre-allocated slots, UKI + TPM encryption, factory reset by discarding keys).
- **bootc/composefs/ostree:** composefs is default in bootc; Fedora 44 "sealed" images (2026-04-28: systemd-boot + UKI + composefs with fs-verity) are test-only, x86_64/aarch64 UEFI. Server/desktop-centric, RPM/OCI-shaped.
- **RAUC** 1.15 (2025-11-07; composefs artifacts since 1.14, HTTP streaming/adaptive updates), **SWUpdate** 2026.05.1 (2026-06-22), **Mender** client 5.1.0 (May 2026). All assume a U-Boot/EFI-style bootloader you control.
- **Nix:** Mobile NixOS received NGI0 funding from Aug 2026 for SDM845 (OnePlus 6) and QCS6490 (Fairphone 5); the maintainer describes the project as "in flux".
- **Verdict:** the **systemd-sysupdate + UKI + A/B + dm-verity** pattern is production-ready in design and shipping in test (GNOME OS, Duranium); bootc is promising but mismatched to phones; RAUC is a solid alternative if you prefer bundles over partition images; Nix is promising for a declarative device database but niche.

### 2.7 Sandboxing: Flatpak, portals, bubblewrap, Landlock, seccomp

- **Flatpak** 1.18.4 (2026-09-28) fixed six CVEs; 1.16.4/1.16.5 (Apr 2026) closed a full sandbox escape (CVE-2026-34078). **xdg-desktop-portal** 1.22.1 (2026-06-17). bubblewrap 0.12. The stack is what Duranium, Mobian, Nura and PureOS use for apps. **Production-ready**, with the caveat that permissions are coarse compared with Android.
- **Landlock:** ABI 11 by the 7.x kernels (TSYNC in 8, pathname UNIX sockets in 9, UDP in 10, atomic no_new_privs in 11). ABI 1 appeared in 5.13, so **android-5.10 vendor kernels have no Landlock at all**. **Promising on Path A; unavailable on many Path B kernels.**
- **seccomp:** universal; Flatpak applies a filter already. Production-ready.

### 2.8 Users, storage, verified boot: systemd-homed, fscrypt, dm-verity

- **fscrypt v2** is what Android uses, what Ubuntu Touch 24.04-2.0 made non-experimental, and what systemd-homed now defaults to. **Production-ready.**
- **systemd-homed** gives per-user LUKS or fscrypt homes with TPM/recovery keys; nobody ships it on a phone yet. **Promising.**
- **dm-verity** for `/usr` is in Duranium with the hash in the UKI; the missing piece everywhere is a verified chain from the Android bootloader to U-Boot (Nura lists it as "pending, needs upstream work"). **Promising.**

### 2.9 Mesa: Freedreno/Turnip, Panthor/PanVK, PowerVR, Zink

- **Mesa 26.0** (2026-02-11) added **Adreno Gen 8** (Snapdragon X2, 8 Elite Gen 5/Adreno 840) to both Freedreno and Turnip; Adreno 7xx (SM8550/SM8650 class) was already there; community Turnip builds for Adreno 830 note gmem hangs. Fairphone 5's Adreno 643 and OnePlus 6's Adreno 630 are mature. **Production-ready for SDM845…SM8650; promising for Gen 8; Adreno 810 (Fairphone 6) unverified.**
- **Panfrost/PanVK + Panthor:** Mesa 26.2.0 (2026-08-05) added Mali G1 series; Mali-G715/Immortalis-G715 (Pixel 8/9 Tensor G3/G4) and G720/G725 are listed as supported, but Vulkan is conformant only on G610 and GLES only on G52/G57/G610. CSF GPUs need the Panthor kernel driver (mainline since 6.10); the Rust **Tyr** driver is its successor-in-progress. **Promising.**
- **PowerVR:** Mesa 25.3 reached Vulkan 1.0 conformance for Rogue; the driver covers A/B-series (AXE-1-16M, BXS/BXM-4-64) and Zink runs on it since 26.1. **Pixel 10's Tensor G5 DXT GPU is not supported.** Avoid for now.
- **Zink:** default GL path on NVK since 25.1; viable fallback wherever only Vulkan exists. Production-ready as a strategy.
- On Path B, Mesa is bypassed for the display path (Android GLES blobs through libhybris); it matters only for Waydroid and software rendering.

### 2.10 Waydroid

Waydroid 1.6.3 (2026-05-28) with Android 13 LineageOS-based images as default and "initial support for Android 16 images"; needs binder and ashmem/memfd in the host kernel. Ubuntu Touch ships it on all Halium 9+ devices. **Production-ready**, with the usual GPU caveats (works best with Mesa on Path A or vendor GLES via libhybris on Path B).

### 2.11 eBPF

Android itself ships BPF programs (netd, `time_in_state`, `gpu_mem`) via its bpfloader on GKI kernels, and LPC 2025/2026 has sessions on BPF-based telemetry and a vendor eBPF module framework; `sched_ext` (6.12+) enables pluggable schedulers. **Production-ready on Path A** (bpftrace/libbpf/Aya for power and wakeup accounting); on Path B BPF exists but is constrained by SELinux policy and old kernels.

### 2.12 OTA infrastructure options

Two credible shapes: (a) **systemd-sysupdate** pulling signed partition/UKI images from a plain HTTPS server with SHA256SUMS, as GNOME OS and Duranium do (delta via `systemd-sysupdate` + casync-style chunking still immature); (b) **RAUC** bundles with HTTP streaming and composefs artifacts, plus hawkBit or a static server. Mender/SWUpdate are fine but add a client and server you must run. Image-based OTA on top of the Android `userdata` partition via U-Boot blkmap (Duranium) is the clever trick that avoids repartitioning retail phones.

---

## 3. What this stack does well

- **Immutable, verifiable, rollback-safe base** is now a solved design in systemd land (sysupdate, repart, UKI, dm-verity, homed) and Nura has shown it runs on Android-bootloader phones.
- **Multimedia** converged: PipeWire for audio and camera, libcamera software ISP, portals for permissions.
- **Rust** is a legitimate choice end-to-end on Path A: kernel drivers, compositor (Smithay), toolkit (Iced/Slint), coreutils, sudo.
- **GPU drivers** for Qualcomm are the best-in-class open mobile drivers, and Arm Mali is catching up fast.
- **App sandboxing** (Flatpak/portals) is mature and audited, with a steady security-fix cadence.
- **Community governance** matured: Nura ASBL, NGI0/NLnet grants (openimsd, Mobile NixOS, q6voiced), Hardware CI.

## 4. What it does badly / lessons learned

- **No modern compositor has a hwcomposer backend.** Path B is stuck with Droidian's wlroots 0.17/0.18 fork or Mir 1.8; every project that tried (KWin, Plasma Mobile) eventually dropped Halium.
- **Telephony on mainline is the weakest layer**: VoLTE is a research daemon, voice-call audio needs per-SoC DSP work, and SM8350+ AudioReach is uncovered.
- **Toolkit fragmentation**: Lomiri (Qt5) has needed five years to approach Mir 2/Qt 6; GNOME mobile is a fork; Flutter never got Wayland upstream; Verso died.
- **Vendor kernels block the modern kernel features** (Rust, Landlock, recent BPF, sched_ext) that make the new stack attractive.
- **Camera on Path A** is still per-device tuning; on Path B it is Android HAL glue.
- Immutable designs **assume you control the bootloader**; on phones the Android ABL is a black box, so verified boot stops at U-Boot.

## 5. Current status as of 2026-10-02 (one-line summary per item)

systemd 262 • Nura (ex-postmarketOS) v26.06, systemd 261, Duranium WIP • Ubuntu Touch 24.04-2.0 (2026-07-24), Mir 1.8/Qt 5, Mir 2 + Qt 6 planned H2 2026 • Droidian 101 (Android 13 base, wlroots 0.17.4) / FuriOS FLX1s shipping • Halium 13 newest documented; no Halium 14 documented • wlroots 0.20.2, phoc 0.58α, Phosh 0.55 • Smithay 0.7, COSMIC 1.8 with touch • KWin/Plasma Mobile 6.6.5 mainline only • Mesa 26.2.4 (Adreno Gen 8, Mali G1, PowerVR Rogue conformant 1.0) • PipeWire 1.6.9, libcamera 0.7.2 • ModemManager 1.24.x, openimsd active, q6voiced starting • Flatpak 1.18.4, xdg-desktop-portal 1.22.1, Landlock ABI 11 • Waydroid 1.6.3 (Android 13 images, Android 16 initial) • Rust no longer experimental in kernel (Dec 2025); Ubuntu 26.10 fully Rust coreutils • Slint 1.18.1, Iced 0.14, Qt 6.11, libadwaita 1.9.2.

## 6. Borrowable ideas for a new OS

1. **Duranium's layout**: EROFS `/usr` + dm-verity hash in a UKI, A/B 5 GB slots, systemd-sysupdate, LUKS2 `/var` + `/home`, installed inside Android `userdata` via U-Boot UEFI + `blkmap`. All GPL/LGPL/MIT.
2. **systemd-sysext/confext** for optional components (debug tools, vendor blobs, Waydroid) instead of a package manager on the base.
3. **systemd-homed with fscrypt v2** for per-user encrypted homes; recovery keys; factory reset by discarding keys.
4. **Flatpak + xdg-desktop-portal + bubblewrap**, with **Landlock** rules added by the compositor/launcher on Path A kernels.
5. **PipeWire + WirePlumber + callaudiod**, and watch **q6voiced** and **openimsd** (both D-Bus adjacent to ModemManager) for Qualcomm calling.
6. **Smithay** (MIT) as the compositor base, borrowing **Catacomb's** gesture/orientation model and **phoc's** protocol set (wlr-layer-shell, xdg-activation, ext-session-lock, input-method-v2/text-input-v3, phosh-private is to be avoided). If Path B is a must, port Droidian's hwcomposer backend logic to Smithay rather than forking wlroots again.
7. **Nura's generic kernels + Hardware CI + "main category" rules** (UEFI boot, upstream kernel, minimal patches, five-person device team) as the device-support model.
8. **Mobile NixOS**-style declarative device descriptions even if you do not use Nix at runtime.
9. **RAUC's signed bundle + HTTP streaming** if sysupdate's delta story is too thin; both are GPL/LGPL.
10. **Waydroid** as the Android-app story; **Zink** as the GL fallback on Vulkan-only GPUs.

## 7. Pitfalls to avoid

- Writing a compositor on a toolkit whose compositor module is GPL-only (Qt Wayland Compositor) unless GPLv3 for the whole shell is acceptable.
- Betting on Flutter or a Rust webview for the shell.
- Choosing Path B and assuming Rust-in-kernel, Landlock, sched_ext or modern BPF are available.
- Forking wlroots for hwcomposer: Droidian already proves this costs 2–3 major versions of lag.
- Shipping a mainline device without a VoLTE plan in a country that has switched off 2G/3G.
- Treating libcamera as "done": every sensor/ISP pair needs tuning, and recent Qualcomm ISPs (CAMSS on SM8xxx) are only partly upstream.
- Trusting Slint's royalty-free licence for an OS shell without written confirmation that it is "mobile", not "embedded".
- Starting with bootc/ostree on a phone: it is RPM/OCI-shaped and assumes a mutable bootloader; sysupdate or RAUC fit better.
- Ignoring Mesa conformance: PanVK is conformant only on G610 and PowerVR DXT (Pixel 10) is unsupported; plan for Zink and GLES fallbacks.
- Relying on GitHub-only or single-maintainer forks (Catacomb moved hosts; Verso archived) without vendoring.

## 8. Sources

Compositors: https://crates.io/crates/smithay · https://github.com/Smithay/smithay · https://linuxiac.com/?p=219071 (COSMIC 1.8 touch) · https://www.linuxcompatible.org/story/cosmic-epoch-180-tagged-system76-syncs-rust-desktop-stack-and-wayland-compositor-overhaul/ · https://github.com/catacombing/catacomb · https://github.com/droidian-images/droidian/releases · https://github.com/droidian/wlroots/branches · https://archlinux.org/packages/?q=wlroots · https://tracker.debian.org/pkg/phoc · https://gitlab.gnome.org/World/Phosh/phoc/-/raw/main/NEWS · https://github.com/canonical/mir/releases · https://gitlab.com/ubports/development/core/hybris-support/mir-android-platform · https://forums.ubports.com/post/44315 · https://invent.kde.org/plasma/kwin/-/merge_requests/551 · https://invent.kde.org/teams/plasma-mobile/issues/-/issues/275 · https://www.phoronix.com/news/Plasma-Mobile-Drops-Halium

Ubuntu Touch / Halium: https://ubports.com/blog/ubports-news-1/ubuntu-touch-24-04-2-0-and-24-04-1-4-release-4007 · https://ubports.com/blog/ubports-news-1/call-for-testing-ubuntu-touch-24-04-2-0-rc-and-24-04-1-4-rc-4005 · https://ubports.com/blog/ubports-news-1/ubuntu-touch-24-04-1-3-release-and-updates-on-ubuntu-touch-24-04-2-0-3996 · https://en.ubunlog.com/?p=57196 · https://docs.ubports.com/porting/introduction/Intro.html · https://halium.org/ · https://github.com/libhybris/libhybris · https://liliputing.com/flx1s-is-a-new-linux-phone-thats-mostly-a-downgrade-from-the-flx1/

Nura / postmarketOS: https://nura.eco/blog/ · https://nura.eco/blog/2026/09/27/nura-rename/ · https://nura.eco/blog/2026/03/17/introducing-duranium/ · https://nura.eco/blog/2026/06/21/v26.06-release/ · https://nura.eco/blog/2026/09/29/road-to-main-category/ · https://nura.eco/blog/2026/05/08/q6voice-project/ · https://nura.eco/blog/2026/02/26/pmOS-update-2026-02/ · https://media.ccc.de/v/all-systems-go-2024-278-systemd-ifying-postmarketos-our-immutable-future-and-why-alpine-is-cooler-than-you-thought

Toolkits: https://github.com/slint-ui/slint/releases · https://github.com/slint-ui/slint/blob/master/LICENSE.md · https://github.com/iced-rs/iced/releases · https://www.phoronix.com/news/Iced-0.14-Rust-GUI-LIbrary · https://doc.qt.io/qt-6/qtwaylandcompositor-index.html · https://doc.qt.io/qt-6.11/license-changes.html · https://archlinux.org/packages/extra/x86_64/libadwaita/ · https://github.com/sony/flutter-embedded-linux · https://phoronix.com/news/Denial-WM-Compositor · https://juejin.cn/post/7644026750097883179 (Flutter Linux Wayland issue status) · https://v2.tauri.app/blog/tauri-verso-integration/ · https://www.youngju.dev/blog/2026-07-17-servo-embedding-crates-io-verso-archived.en

Rust: https://lkml.iu.edu/2512.1/04944.html · https://devclass.com/2025/12/15/rust-boosted-by-permanent-adoption-for-linux-kernel-code/ · https://www.phoronix.com/news/Linux-7.2-DRM-Rust · https://www.phoronix.com/news/NVIDIA-Nova-Rust-Linux-7.3 · https://www.phoronix.com/news/ubuntu-25.10-rust-coreutils · https://discourse.ubuntu.com/t/adopting-sudo-rs-by-default-in-ubuntu-25-10/60583 · https://www.drweb.de/ubuntu-26-10-rust-coreutils/

Audio/camera/telephony: https://phoronix.com/news/PipeWire-1.6 · https://archlinux.org/packages/extra/x86_64/pipewire/ · https://archlinux.org/packages/extra/x86_64/libcamera/ · https://libcamera.org/ · https://archlinux.org/packages/extra/x86_64/modemmanager/ · https://nlnet.nl/project/VoLTE-Qualcom/ · https://www.openimsd.de/ · https://tracker.debian.org/media/packages/8/81voltd/control-1.2.0-1 · https://gitlab.freedesktop.org/mobile-broadband/ModemManager/-/merge_requests/653

Immutable/OTA/security: https://raw.githubusercontent.com/systemd/systemd/main/NEWS · https://discourse.gnome.org/t/why-did-gnome-os-choose-systemd-sysupdate-over-bootc/24642 · https://fedoramagazine.org/sealed-atomic-desktops-test-images/ · https://gitlab.com/fedora/ostree/sig/-/issues/35 · https://pengutronix.de/en/blog/2025-04-09-rauc-v1-14-released.html · https://rauc.readthedocs.io/en/latest/changes.html · https://github.com/sbabic/swupdate/releases · https://github.com/mendersoftware/mender/releases · https://nlnet.nl/project/MobileNixOS-SDM845-QCS6490/ · https://github.com/flatpak/flatpak/releases/tag/1.18.4 · https://github.com/flatpak/xdg-desktop-portal/releases · https://docs.kernel.org/userspace-api/landlock.html · https://kernsec.org/pipermail/linux-security-module-archive/2026-February/055527.html

GPU/Waydroid/eBPF: https://docs.mesa3d.org/relnotes/26.0.0.html · https://docs.mesa3d.org/relnotes/26.2.0.html · https://www.phoronix.com/news/Mesa-26.0-Adreno-Gen-8-Graphics · https://docs.mesa3d.org/drivers/panfrost.html · https://www.phoronix.com/news/Mesa-25.1-Newer-Mali-5th-Gen · https://docs.mesa3d.org/drivers/powervr.html · https://developer.imaginationtech.com/solutions/open-source-gpu-driver/ · https://phoronix.com/news/PowerVR-Vulkan-Does-Zink · https://github.com/waydroid/waydroid/tags · https://source.android.com/docs/core/architecture/kernel/bpf · https://lpc.events/event/20/contributions/2557/ · https://lpc.events/event/19/contributions/2118/

Unverified or weakly sourced items (flagged in text): exact Mir 2.30 release year (GitHub shows "Sep 24" without year; inferred 2026); GNOME Shell mobile status beyond the `48.mobile.0` version string in Nura v26.06; Halium 13 stability (forum statements only); Adreno 810 (Fairphone 6) support in Freedreno; Mali-G715 PanVK quality on Pixel 8/9.
