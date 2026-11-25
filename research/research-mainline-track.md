# The mainline-Linux track: postmarketOS (now Nura), Mobian, PureOS, Phosh, Plasma Mobile

Status date: 2026-10-02. Everything below was checked against 2025-2026 sources where possible; items I could not verify are marked **unverified**. Note on naming: on 2026-09-27, at the postmarketOS and Alpine Linux Conference in Aachen, postmarketOS was renamed **Nura** (from "nuraghe"); the web properties moved to nura.eco / docs.nura.eco / wiki.nura.eco / pkgs.nura.eco, a trademark was filed, and the packages, `pmbootstrap` and `pmaports` keep their old names during the transition. I use "pmOS/Nura" below.

---

## 1. Architecture

### Layers (pmOS/Nura, which is the reference design; Mobian and PureOS differ mainly in the base distro)

| Layer | pmOS/Nura | Mobian | PureOS |
|---|---|---|---|
| Base distro | Alpine Linux 3.24 (musl, apk, busybox, LLVM 22, Rust 1.96) | Debian 13 "trixie" (glibc, apt) | Debian-derived; Crimson (Debian 12) released May 2026, Dawn (Debian 13) in development |
| Init | systemd 261 (patched for musl); OpenRC still buildable but deprecated for Plasma, kept for Sxmo | systemd | systemd |
| Kernel | Per-SoC "close-to-mainline" packages (e.g. `linux-postmarketos-qcom-sdm845` at 7.1) and, since Feb 2026, generic `linux-postmarketos-{mainline,stable,lts}` | Debian 6.12 kernel for almost all devices; Librem 5 on 6.6 | Librem 5 vendor-maintained kernel |
| Boot | ABL (Android bootloader) -> boot.img, or ABL -> U-Boot disguised as a kernel -> EFI; Duranium (immutable) uses systemd-efistub + erofs | u-boot / device-specific | u-boot (Librem 5) |
| Telephony | ModemManager 1.24 + libqmi over QRTR, rmtfs, imsd/81voltd (IMS, experimental), callaudiod, feedbackd | same | same |
| Audio | PipeWire/WirePlumber with ALSA UCM profiles per device (ADSP/Q6 on Qualcomm) | same | same |
| Graphics | Mesa Freedreno/Turnip (Adreno), Panfrost/Panthor (Mali) | same | Etnaviv (i.MX8M) |
| Camera | kernel `qcom-camss` + libcamera software ISP; Megapixels or Plasma Camera | same | same |
| Shell | Phosh (phoc/wlroots), Plasma Mobile (KWin), GNOME Mobile (patched gnome-shell, experimental), Sxmo (sway/dwm) | Phosh, Plasma Mobile | Phosh |

### How a device port is defined and packaged (pmaports)

- A port is a directory `device/<category>/device-<vendor>-<codename>/` in the `pmaports` git repo with an `APKBUILD` (Alpine package recipe) and a `deviceinfo` shell-style key/value file (`deviceinfo_codename`, `deviceinfo_arch`, `deviceinfo_screen_width`, `deviceinfo_dev_touchscreen`, `deviceinfo_bootimg_qcdt`, flash method, kernel cmdline, etc.). The deviceinfo schema is validated by a tool called `dint`, which since Feb 2026 also generates the official "Deviceinfo Reference" docs from one source file. Optional subpackages carry udev rules, ALSA UCM, initramfs hooks and a "nonfree-firmware" subpackage.
- The device package depends on a kernel package (either `linux-<vendor>-<codename>` for a downstream/forked kernel or a shared SoC kernel such as `linux-postmarketos-qcom-sdm845`) and on firmware packages (`firmware-<vendor>-<device>`, `soc-qcom-<soc>-nonfree-firmware`). Firmware policy, in priority order: (1) use upstream `linux-firmware`; (2) package the blobs in pmaports; (3) extract unit-specific calibration/regional files from the device's own partitions at boot with `msm-firmware-loader`. Non-free firmware has been installed by default since early 2024 and must be in `depends`, not optional.
- Kernel configs are no longer hand-maintained: fragment-based configuration merges `kconfigcheck.toml` (project-wide invariants, checked by `pmbootstrap kconfig check`) and `kconfig-generic.toml` on top of the arch defconfig. For generic kernels "out-of-tree or non-upstreamable patches are unacceptable."
- `pmbootstrap` (Python, GPLv3; v3.0.0 was a rewrite, v3.10.0 shipped March 2026) creates Alpine chroots on the host, cross-builds packages with `apk.static` + QEMU user mode, assembles rootfs/boot images and flashes via fastboot/heimdall/etc. `pmbootstrap aportgen device-*|linux-*` scaffolds a new port; `pmbootstrap init` is the wizard. PyPI releases are deprecated; install from git or distro packages.
- Device tiers: **testing** (must build and boot, close-to-mainline kernel at least as new as the oldest supported kernel.org LTS, compiled with LLVM); **community** (passes `kconfig check --community` including firewall, kernel not older than 6 months and upgraded through 3+ releases, automatic kernel upgrades, documented install, maintainer joins release testing); **main** (PMCR-0009, still draft: UEFI boot, generic kernel, generic device package with no device-specific forks, hardware CI in 2 locations with 3+ devices, a 5-person maintainer team). As of v26.06 **no device is in main**. Unmaintained devices are archived after v26.06 with a 3-month claim window.
- Generic device packages: `device-generic-<arch>` (x86_64 today) and SoC-level groups such as `qcom-qcs6490` (Radxa Dragon Q6A, promoted to community March 2026), `qcom-msm8953` and `qcom-sm7150`. Device-specific daemons must self-gate, e.g. `hexagonrpcd` (serves HexagonFS to the DSPs for sensors) starts only if `/dev/fastrpc-adsp` exists.

### How hardware is reached on a Qualcomm phone

ABL loads a boot image. Either it contains the Linux kernel + DTB directly, or it contains U-Boot "disguised as a Linux kernel" (Linaro's trick, so ABL chainloads it without touching secure boot) which then offers an EFI boot flow; the SM8650 work "integrated U-Boot upstream support and the standard EFI boot flow." Qualcomm subsystems (modem, ADSP, CDSP) are remoteprocs booted by the kernel with signed firmware; the modem speaks QMI over QRTR (`qrtr-ns`, `pd-mapper`, `rmtfs` for the modem's EFS, `tqftpserv`). GPU needs `firmware-qcom-adreno-*` plus a per-device "zap shader." Sensors are reached via FastRPC and `hexagonrpcd`. Cameras are V4L2 media graphs (CSIPHY -> CSID -> VFE/IFE/TFE) exposed by `qcom-camss` and consumed by libcamera.

---

## 2. What it does well

1. **Single-tool developer loop.** `pmbootstrap` gives one reproducible chroot/build/flash workflow across 300+ devices; incremental builds (`--src`), GPT images, run0 support, UEFI default for QEMU.
2. **Honest device tiers and archival.** The testing/community/main ladder plus the 2026 archival policy keep the repo honest about what works; v26.06 lists ~50 community devices and 254 testing devices and demoted five for stale kernels.
3. **Upstream-first culture that actually lands patches.** David Heidelberg alone had 155 touches in 6.7 -> 7.0 (Pixel 3 DT from scratch, panel drivers, NFC for Pixel/OnePlus/SHIFT). Fairphone (Luca Weiss) posted FP6 patches the day it launched. Mobian's declared goal is to "abolish itself" by upstreaming everything into Debian.
4. **Generic kernels and fragment configs** (2026) collapse per-device kernel maintenance; `kconfigcheck` enforces security/feature baselines automatically.
5. **Hardware-in-the-loop CI** exists now: CI-tron (Valve/Mesa's system) plus a custom phone-harness PCB/PDU; OnePlus 6T and 6 run reboot/kernel-upgrade tests in GitLab before merge; docs and a hardware request process are published.
6. **UI-agnostic stack.** Phosh, Plasma Mobile, GNOME Mobile and Sxmo all run on the same ModemManager/callaudiod/feedbackd/PipeWire/libcamera plumbing; the UI is a `postmarketos-ui-*` package chosen at `pmbootstrap init`.
7. **Immutable variants are emerging:** Duranium (erofs + systemd-efistub + systemd sysext; Waydroid installed as an extension with `updatectl enable waydroid`; bootctl fallback entries; NLnet-funded) and Phosh's BengalOS (nightly image-based, A/B upgrades demoed at FrOSCon 2026).
8. **Modern plumbing adopted quickly:** systemd (on musl!), Plymouth replacing pbsplash, sudo-rs by default, greetd/phrog instead of tinydm, PipeWire, the Rust `usb-signaller` replacing `usb-moded`.
9. **Real SoC vendor engagement.** Qualcomm/Linaro posted mainline support for 8 Gen 2 (Nov 2022), 8 Gen 3 (Oct 2023), 8 Elite (Oct 2024), 8 Elite Gen 5 (same day, Sept 2025) and from March 2026 for unannounced SoCs ("Hawi", "Maili"). Turnip is Vulkan 1.3-conformant on A6xx and 1.4 on A7xx and will ship in AOSP's `external/mesa3d`.
10. **Governance maturing:** Trusted Contributors assembly, a legal entity being formed, NLnet/NGI Zero Core funding, a Phosh.mobi e.V. nonprofit.

---

## 3. What it does badly / lessons learned

1. **Nine years, zero "main" devices.** The project itself concluded that "getting features to work at all" was solved but reliability was not, hence the UEFI + generic-kernel + hardware-CI redefinition of main. Lesson: define "supported" by reliability metrics and CI, not by a feature checklist.
2. **SoC support is not phone support.** Snapdragon 8 Gen 3 is "fully featured" upstream (Hexagon DSPs, Adreno 750, runtime PM, suspend-to-RAM) and was demoed on a retail phone at FOSDEM 2026, yet I could find no community-tier phone port on SM8450/8550/8650/8750. Panel, touch, charger, audio routing (ALSA UCM), camera sensors, haptics, NFC and fingerprint are per-device work that vendors do not post. The FP6 still has a broken fingerprint reader and selfie camera after 15 months.
3. **Audio is the long pole.** Fairphone's 2026 verdict: "Audio is the most significant pain point now" (speaker, mic, call audio) on FP4/FP5; v26.06 known issues include Fairphone 3 volume and DTMF failures. ADSP/Q6 topologies and UCM files are tedious and undocumented.
4. **Camera quality is years behind.** Even the celebrated FP6 result is "very grainy," with colour correction in progress; libcamera's SoftISP runs debayer on CPU/GPU (~30 fps with GPU) because Qualcomm's Titan/IFE post-processing is undocumented. The first FOSS stack for a Qualcomm hardware ISP (the OPE on QRB2210) only appears in 2026.
5. **VoLTE/IMS is still reverse engineering.** `imsd` is "a reverse engineered FOSS implementation of proprietary Android IMS implementations"; every modem vendor differs. FP6 managed an emergency VoLTE call in Aug 2026; Ubuntu Touch's Pixel 3a got its first VoLTE call in April 2026. With 2G/3G sunsets this is existential, and it is still experimental.
6. **Suspend and battery life are not solved.** OnePlus 6 reports "higher idle drain than the Pixel 3a" and the modem not reaching its deepest sleep; one community report cites roughly 12-14 h idle with autosuspend on Mobian (**unverified**, secondhand). ModemManager 1.24 added low-power mode during suspend, and SM8650 upstream claims suspend-to-RAM, but phone-level standby parity with Android is not demonstrated anywhere.
7. **Mainline can regress old devices.** FP2's GPU "doesn't work anymore since v6.17 (vram carveout was removed)" and now hard-requires IOMMU support nobody has written for msm8974. Longevity promises need a maintainer budget.
8. **Maintainer burnout and churn.** Two founders of Android and Chromebook support (Minecrell, Anton) left the Technical Committee in early 2026; devices are archived when maintainers vanish. armhf was dropped from edge.
9. **musl is a tax.** systemd on musl needs project-carried patches; Alpine has no systemd and ships GTK3 to community. Mobian's counter-lesson: being a thin overlay over Debian means major upgrades are painful enough that the team recommends fresh installs.
10. **Polish gap acknowledged.** v26.06 notes it targets "mainly Linux enthusiasts." GNOME Mobile is still "experimental" and lags (48.mobile on a GNOME 50 base). Plasma Mobile needed "at least 9 crash fixes" in one week of Jan 2026.
11. **Policy friction for newcomers:** the development AI policy now "explicitly forbid[s] generative AI" in contributions. If your new OS is built with AI assistance, upstreaming into pmaports/Nura will be a problem; the kernel, Mesa and libcamera have their own evolving rules.

---

## 4. Current status as of 2026-10-02

**Distros**
- **Nura (ex-postmarketOS) v26.06 "Alpen Avocado"**, 2026-06-21: Alpine 3.24, systemd 261, GNOME 50 (GNOME Mobile 48.mobile.0), Plasma Mobile 6.6.5, Phosh 0.55.0, Sxmo 1.18.1, Plymouth, sudo-rs, ModemManager with Cell Broadcast; generic kernel packages supported for the release lifetime. Edge has Plasma 6.7, sdm845 kernel 7.1, Duranium v21 (built 2026-10-01), `usb-signaller`. Rename announced 2026-09-27.
- **Mobian Trixie** (2025-10-13): Phosh and Plasma Mobile 6.3 on kernel 6.12; full images for PinePhone/Pro, PineTab, Librem 5, Pixel 3a/3a XL, OnePlus 6/6T, Poco F1; FP4/FP5/PineTab 2/SHIFT6mq partial (Wi-Fi/audio gaps); `mobian-recipes` for custom encrypted images; key rotation under way.
- **PureOS Crimson** released May 2026 after a 2+ year slip; Dawn (Debian 13) in development with Phosh/phoc 0.55. Librem 5 (i.MX8M, 2019) remains the only Purism phone.
- **Fedora Mobility / Pocketblue**: bootc-based images; Fedora 44 with GNOME shown on FP6 with all three cameras (Aug 2026).

**Shells**
- Phosh 0.57.0 (late Aug 2026; unified settings app); phoc 0.58 alpha, xdg-desktop-portal-phosh 0.58, gmobile 0.7.4, Stevia OSK with clipboard history, text-input-v3 v2 in phoc/wlroots; six-week cadence; BengalOS immutable nightlies adding Pixel 3/3a, SHIFT6mq.
- Plasma Mobile tracks Plasma 6.7.4 (2026-08-04); Dialer/Spacebar in the Plasma cycle since 6.2; Plasma Camera on libcamera; NFC integration announced Aug 2026; kde-nightly repo on Nura.
- GNOME Mobile: experimental patched gnome-shell/mutter; conference talk 2026-09-27 on convergence with upstream.
- Sxmo 1.18.x: sway/dwm, OpenRC, everything scriptable.

**SoCs and devices (mainline)**
- **Snapdragon 845 (SDM845)**: the reference platform. OnePlus 6/6T, Pixel 3/3 XL, Poco F1, Mi Mix 2S, SHIFT6mq, Galaxy S9 share `linux-postmarketos-qcom-sdm845` (7.1). NFC merged for 7.x; OnePlus 6/6T are community tier and the hardware-CI devices. Modem/calls/SMS/data/GPU/Wi-Fi work; suspend drain and camera remain weak.
- **Snapdragon 865 (SM8250)**: OnePlus 8T on mainline, Minecraft at 25 fps (Aug 2026). **SM8350** (OnePlus 9): archived, 3D broken.
- **QCM6490/QCS6490 (FP5, Radxa Dragon Q6A)**: generic `qcom-qcs6490` package; Dragon Q6A in community; FP5 "mostly Works, some Partial," audio partial, camera partial, patches going upstream; verdict "daily driver now or hopefully soon." **FP4 (SM7225)** similar with audio/VCM focus-coil work pending. **FP3** (msm8953) partial; **FP2** effectively EOL on mainline.
- **SM7635 (FP6)**: same-day vendor patches (June 2025); Jan 2026: display partial, GPU/audio/camera/sensors broken; by Aug 2026 (edge): all three rear cameras via `qcom-camss` + SoftISP (TFE665 found register-compatible with TFE530), audio, VoLTE emergency call via imsd; still broken: selfie camera, fingerprint.
- **SM8450/8550/8650/8750/8850 (8 Gen 1 through 8 Elite Gen 5)**: platform support upstream (CPU/DVFS, UFS 4, PCIe, USB, WCN7850, DSPs, Adreno 750, suspend-to-RAM, U-Boot/EFI). Retail-phone demo at FOSDEM 2026. No community-tier phone port found; Galaxy Tab S8+ (SM8450) bring-up exists. Adreno A8xx (8 Elite) Vulkan is **out-of-tree experimental** (whitebelyash gen8 stack), not upstream Mesa; A7xx (8 Gen 3) is upstream and conformant.
- **Google Tensor**: GS101 (Pixel 6) in mainline since 6.8; Nura has `linux-postmarketos-gs101` "close-to-mainline"; no Phosh-grade daily use reported. Tensor G3/G4 (Pixel 8/9, "zuma"): no mainline device trees found (**unverified**). Tensor G5 (Pixel 10): a Google Chromium engineer posted initial DTs (~Nov 2025) that boot to a UART initramfs prompt with a "yet-unreleased bootloader"; GPU is Imagination DXT, open-driver status unknown. Pixel 9a ultrawide camera photos were reported on a Linux stack in Aug 2026 (**unverified**, single linmob mention).
- **MediaTek**: only forks for MT6768/MT6763 and Chromebook SoCs (Asurada/Cherry/Corsola added in v26.06); no Dimensity flagship phone on mainline found. MediaTek's upstream effort centres on Chromebook SoCs (**from prior knowledge, unverified for 2026**).

**Plumbing**
- ModemManager 1.24.x: QRTR control ports, Cell Broadcast API, low-power mode during suspend, eSIM profile handling. libqmi >= 1.32 for QRTR.
- IMS: `imsd` (GPLv3, QMI/QRTR, VoLTE + SMS-over-IMS, Qualcomm/MediaTek/Samsung modem notes) and `81voltd` (minimal IMS Data service; limitations: stopping it does not release bearers, MM errors not propagated). Both experimental.
- libcamera 0.7.1: multithreaded SoftISP debayer; new CAMSS pipeline handler (Apr 2026); Qualcomm OPE hardware-ISP driver series (Apr 2026, OSS EU Oct 2026). Megapixels 2.1 on edge.
- Mesa 26.x: Freedreno/Turnip A6xx Vulkan 1.3 conformant, A7xx 1.4; Adreno X2-85 driver work for 7.1.
- U-Boot: Linaro's Qualcomm port (Caleb Connolly maintainer) chainloads from ABL as a fake kernel, offers EFI; goal is U-Boot as primary bootloader.

**What is actually hard, in priority order:** per-device audio routing; VoLTE/IMS per modem vendor; standby power (modem/DSP sleep states, wake sources); camera ISP documentation and tuning; GPU firmware/zap shaders and A8xx driver; secure-boot/bootloader lock on new OnePlus/Pixel; keeping old devices from regressing; maintainer continuity; UI polish.

---

## 5. Borrowable ideas for a new OS

Concrete components (licenses in parentheses):

1. **Build/flash tool pattern**: reimplement `pmbootstrap`'s model (host chroots, `apk.static` + QEMU user, scaffolding generators, `kconfig check`, GPT image assembly) in Go. Keep `deviceinfo`-style declarative device descriptors plus a validator like `dint` that also emits docs. (pmbootstrap GPLv3; your reimplementation can be your own license.)
2. **Device tiers with teeth**: testing / community / main with machine-checkable criteria (kernel age, LLVM build, kconfig fragments, auto-upgrade test, hardware CI) and an archival policy.
3. **Generic kernel + fragment configs**: one `linux-stable`/`linux-lts`/`linux-mainline` set, DTBs from the kernel tree, `kconfigcheck.toml`-style invariants, and a rule that only upstream or upstream-bound patches are allowed. (Kernel GPLv2.)
4. **Boot chain**: ABL -> U-Boot-as-fake-kernel -> EFI -> systemd-boot/efistub, with `bootctl` fallback entries. (U-Boot GPLv2+, systemd LGPL-2.1+.) This is what the "main" category will require, so align early.
5. **Immutable image design from Duranium/BengalOS**: erofs root, systemd-efistub, `systemd-sysupdate` for A/B, `systemd-sysext` for optional layers (Waydroid as an extension is a nice trick), image builder (`coldbrew`/`f0rmz` in Nura; Fedora's `bootc` is the glibc-world alternative). This fits "newer technology" without inventing a new OS updater.
6. **Hardware CI**: CI-tron (Valve/Mesa, MIT-style) plus the Nura phone-harness PCB (open hardware, docs at docs.nura.eco/hardware-ci and /phone-harness). Budget two locations from day one.
7. **Firmware policy**: upstream `linux-firmware` first; packaged blobs second (`soc-qcom-*-nonfree-firmware`, BSD-3-Clause redistribution with no-reverse-engineering terms); `msm-firmware-loader` to pull unit-specific calibration from device partitions at boot.
8. **Telephony stack**: ModemManager 1.24+ (GPLv2/LGPL-2.1) + libqmi + kernel QRTR + `rmtfs`/`qrtr-ns`/`pd-mapper`/`tqftpserv` + `imsd` (GPLv3) or `81voltd` for IMS; `callaudiod` and `feedbackd` (GPLv3) for call audio routing and haptics; `mobile-broadband-provider-info` for emergency numbers.
9. **Sensors/DSP**: `hexagonrpcd` + HexagonFS over FastRPC, self-gated on `/dev/fastrpc-adsp`.
10. **Camera**: `qcom-camss` + libcamera (LGPL-2.1) SoftISP with GPU path; the new CAMSS pipeline handler; Megapixels (GPLv3) or Plasma Camera as reference apps; follow Qualcomm's OPE driver as the first hardware-ISP template.
11. **Graphics**: Mesa Freedreno/Turnip (MIT); Vulkan 1.4 on A7xx; plan for A8xx being out-of-tree for now.
12. **Compositor choices to evaluate on merit**: phoc (wlroots, GPLv3) with gmobile device quirks and `xdg-desktop-portal-phosh`; KWin (GPL-2.0+) if you want Qt/QML; both implement the Wayland protocols you need (text-input-v3 v2, layer-shell, input-method, screencopy). Phosh's `phrog`/greetd login path and Stevia OSK are reusable regardless of shell.
13. **Small modern defaults that Nura already validated**: sudo-rs, Plymouth with DRM rendering, PipeWire/WirePlumber, Rust `usb-signaller` for USB gadget/role switching.
14. **Upstream-first as policy**: Mobian's "thin overlay" model (declared aim to abolish itself) keeps your delta small; Fairphone's same-day patch posting shows what vendor cooperation looks like.
15. **Governance**: Trusted Contributors assembly, written CoC team, legal entity, NLnet/NGI Zero applications; publish a clear AI-contribution policy before contributors arrive, in whichever direction you choose.

---

## 6. Pitfalls to avoid

1. **Choosing a target phone by SoC headline.** "Upstream supports 8 Gen 3" does not mean any 8 Gen 3 phone has display, touch, audio or modem on mainline. Pick devices with an existing community-tier port and an engaged vendor (Fairphone 5/6 today), or budget a year per device for enablement.
2. **Per-device kernel forks.** They are what forced the 2026 generic-kernel reset and the demotion of devices with stale kernels. Start with generic kernels and DTB-only device packages.
3. **Underestimating audio, IMS and standby.** These are the three items every 2026 status report still lists; schedule them before UI polish.
4. **Treating libcamera SoftISP as "camera done."** Output is grainy and power-hungry; tuning files and hardware ISP support are long-term work.
5. **Skipping hardware CI.** Without it you cannot credibly call anything stable; Nura spent 2025-2026 building it and still has no main device.
6. **musl without a plan for systemd/GNOME/KDE dependencies**, or Debian without a plan for upgrade pain. If you go Alpine-style, carry the systemd-on-musl patches knowingly; if you go glibc, look at Fedora bootc/Pocketblue rather than a plain Debian overlay.
7. **Assuming old devices stay supported.** Mainline removed the vram carveout in 6.17 and broke FP2 graphics; longevity requires a maintainer, not just a mainline DT.
8. **Firmware licensing as an afterthought.** Qualcomm blobs are redistributable under BSD-3-Clause-style terms with conditions; per-unit calibration must be read from the device, not shipped.
9. **Expecting bootloader unlock to remain available** on OnePlus/Pixel-class hardware; the mainline track increasingly assumes Fairphone, dev kits (Radxa Dragon Q6A) and older flagships.
10. **One-shell lock-in.** Keep ModemManager/callaudiod/feedbackd/libcamera/PipeWire as the contract so Phosh, Plasma Mobile, GNOME Mobile or your own shell can sit on top.
11. **Ignoring the generative-AI contribution policy** of the projects you need to upstream into (Nura forbids it); decide how you will handle this before you need a patch merged.
12. **Rebranding late.** postmarketOS took 18 months and 300 suggestions to become Nura; pick a trademarkable name early.

---

## 7. Sources

Nura / postmarketOS
- https://nura.eco/blog/2026/06/21/v26.06-release/ (v26.06 release notes)
- https://nura.eco/blog/2026/02/26/pmOS-update-2026-02/ (generic kernels, hardware CI docs, AI policy, PMCR-0009)
- https://nura.eco/blog/2026/04/05/pmOS-update-2026-03/ (Dragon Q6A community, pmbootstrap 3.10.0, Duranium, Plymouth, archival policy)
- https://nura.eco/blog/2026/07/06/pmOS-update-2026-06/ (Duranium sysext/Waydroid, sdm845 kernel 7.1, usb-signaller, armhf removal, LLVM/LTS rules)
- https://nura.eco/blog/2026/02/10/fosdem-and-hackathon/ (CI-tron, phone harness, FP5 call audio, PipeWire)
- https://docs.nura.eco/pmaports/main/packaging/device-categorization.html
- https://docs.nura.eco/pmcr/main/0009-new-main-device-category.html
- https://docs.nura.eco/pmaports/main/packaging/kernel-packages/generic-kernel-packages.html
- https://docs.nura.eco/pmaports/main/packaging/device-packages/generic-device-packages.html
- https://docs.nura.eco/pmaports/main/packaging/firmware-packages.html
- https://pkgs.nura.eco/package/main/postmarketos/x86_64/postmarketos-duranium
- https://pkgs.postmarketos.org/package/main/postmarketos/aarch64/linux-postmarketos-gs101
- https://pkgs.postmarketos.org/package/v25.12/postmarketos/aarch64/linux-postmarketos-mediatek-mt6768
- https://gitlab.postmarketos.org/ijiki16/pmbootstrap/-/tags/3.0.0 (pmbootstrap 3.0.0 notes)
- https://pypi.org/pypi/pmbootstrap/json (PyPI deprecation)
- https://postmarketos.org/blog/2024/05/26/the-road-to-systemd/
- https://linuxiac.com/?p=220036 and https://www.notebookcheck.net/postmarketOS-is-now-Nura-after-nearly-a-decade-of-bringing-Linux-to-phones.1410027.0.html (rename)
- https://archive.fosdem.org/2026/events/attachments/QUYXW7-postmarketos-reliability-2026/slides/266958/postmarke_nwxmydf.pdf (reliability talk; not fetched, too large)
- https://pretalx.postmarketos.org/postmarketos-conference-2026/talk/8JEXAH/ (GNOME Mobile talk)
- https://pretalx.postmarketos.org/postmarketos-conference-2026/talk/8SQD7X/ (BengalOS road show)

Fairphone / Qualcomm / kernel
- https://archive.fosdem.org/2026/schedule/event/ZNAAZX-mainline_kernel_for_fairphones_-_2026_update and slides fosdem_20_rsemaak.pdf (Luca Weiss)
- https://archive.fosdem.org/2026/schedule/event/SXNNMZ-snapdragon_8_gen_3_mainline_from_day-1_patches_to_product_reality/ (Neil Armstrong)
- https://www.cnx-software.com/?p=119866 (8 Gen 3 initial upstream, Oct 2023)
- https://social.kernel.org/notice/B9IAbZSB83mW5tiyhs (Krzysztof Kozlowski on Qualcomm posting pre-announcement SoCs)
- https://www.phoronix.com/news/Fairphone-6-Linux (same-day FP6 patches; blocked for fetch, cited from search)
- https://byteiota.com/fairphone-6-postmarketos-camera-works-no-blobs-needed/ (FP6 camera, TFE665/TFE530)
- https://linmob.net/weekly-update-34-2026/ (FP6 cameras/audio/VoLTE, OnePlus 8T, Pixel 9a)
- https://linmob.net/weekly-update-14-2026/ (NFC on SDM845, Ubuntu Touch VoLTE on Pixel 3a, pmbootstrap 3.10.0)
- https://linmob.net/weekly-update-04-2026/ (hardware CI MVP, Duranium first boot)
- https://ixit.cz/blog/2026-04-03-kernel-7-0-contribution.md (SDM845 phones in 7.0)
- https://www.notebookcheck.net/Fairphone-6-turns-into-a-Linux-phone-running-Fedora-44-with-working-cameras.1372181.0.html
- https://phoronix.com/news/Linux-6.8-GS101-SoC-Pixel-6 and https://phoronix.com/news/Google-Pixel-10-Google-DTs (Tensor; blocked for fetch, cited from search and https://scribe.disroot.org/comment/7852066)
- https://wiki.postmarketos.org/wiki/OnePlus_9_%26_9_Pro_(oneplus-lemonade_%26_oneplus-lemonadep) and https://wiki.postmarketos.org/wiki/OnePlus_8T_(oneplus-kebab)
- https://times.ferdios.kroket.io/hardware/oneplus6 (OnePlus 6 idle drain note)
- https://www.linaro.org/blog/initial-u-boot-release-for-qualcomm-platforms/ (U-Boot chainload via ABL)
- https://archive.fosdem.org/2024/schedule/event/fosdem-2024-1716-u-boot-for-modern-qualcomm-phones/

Modem, camera, GPU
- https://sources.debian.org/src/modemmanager/1.24.2-2/NEWS
- https://zff.dev/flamingradian/imsd
- https://manpages.debian.org/trixie/81voltd/81voltd.1.en.html
- https://phoronix.com/news/libcamera-0.7.1-Released (via search)
- https://lwn.net/Articles/1069985/ (Qualcomm OPE driver series, Apr 2026)
- https://osselceu2026.sched.com/event/2Rab2 (OPE FOSS ISP stack talk)
- https://archive.fosdem.org/2026/schedule/event/TKSK3G-libcamera-softisp/
- https://patchwork.libcamera.org/patch/26512/ (CAMSS pipeline handler)
- https://memcpy.io/upstream-camera-support-for-qualcomm-platforms.html (CAMSS background, 2021)
- https://www.collabora.com/news-and-blog/news-and-events/mesa-on-android-how-we-brought-turnip,-skiavk,-and-cuttlefish-to-ci.html (Turnip conformance, Sept 2026)
- https://github.com/The412Banner/Banners-Turnip/releases (A8xx out-of-tree status)

Shells and other distros
- https://phosh.mobi/posts/development-news-2026-08/ and https://phosh.mobi/posts/development-news-2026-09/
- https://en.wikipedia.org/wiki/Phosh (0.57.0 date)
- https://plasma-mobile.org/blog/ and https://en.wikipedia.org/wiki/Plasma_Mobile
- https://sxmo.org/
- https://blog.mobian-project.org/posts/2025/10/new-stable-rotating-keys/
- https://archive.fosdem.org/2025/schedule/event/fosdem-2025-4129-mobian-upstream-first-and-the-greater-good
- https://puri.sm/posts/pureos-crimson-development-report-april-2026-pureos-crimson-released/ and https://puri.sm/posts/pureos-development-report-may-2026/
- https://www.fedoraproject.org/wiki/Mobility
- https://alpinelinux.org/posts/Alpine-3.24.0-released.html
- https://forums.puri.sm/t/new-immutable-mobile-os-postmarketos-duranium-and-phosh-bengalos/30912
