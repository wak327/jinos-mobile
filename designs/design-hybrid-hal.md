# Design proposal "Isthmus": one OS image, two hardware tracks, joined by an OS-owned hardware contract

Key: `hybrid-hal` · Written 2026-10-03 · Angle: pluggable hardware abstraction inspired by OpenHarmony HDF/HDI, Android Treble and Fuchsia

> **Provenance warning.** The six research reports this design was supposed to build on (`research-*.md` in the `mobile-os` scratch directory) did not exist when this was written — the scratch directory had been wiped and was empty. Rather than design from stale memory, I re-verified the load-bearing facts by web search on 2026-10-03 and cite them inline. Anything marked *unverified* I could not confirm. If the reports are regenerated, sections 1, 4 and 7 should be re-checked against them.

## 0. Thesis in one paragraph

An isthmus is a narrow strip of land joining two landmasses. The two landmasses here are the **mainline-kernel world** (Nura/postmarketOS, Mobian: open drivers, 3-6 years late) and the **Android-vendor world** (Halium, Ubuntu Touch, Droidian, FuriOS: day-one hardware, closed blobs). Today every mobile Linux shell is welded to one side: Phosh and Plasma Mobile expect ModemManager, so Droidian had to write `ofono2mm`, a Python daemon that fakes the ModemManager D-Bus API on top of oFono (https://github.com/droidian/ofono2mm); Lomiri expects oFono, repowerd and the Mir Android platform. Isthmus makes the seam explicit and owned by the OS: a small, versioned **Hardware Contract (HC)** with a conformance suite, and per-capability **providers** in two flavours. Everything above the contract — one byte-identical OS image, shell, apps, portals, updater — is the same on both tracks. The user-visible payoff: **a phone starts on vendor drivers on day one and migrates to mainline in place when upstream catches up, without reinstalling**. The phone gets more free as it ages instead of more abandoned.

The guiding rule that keeps this affordable for one developer: **adopt, don't invent**. Where a de-facto Linux API already spans both tracks (nl80211, BlueZ, PipeWire, libinput), that API *is* the contract. An OS-owned interface is written only where no single upstream API covers both tracks (telephony, sensors, power, camera control, biometrics, NFC, haptics, location).

## Layer table

| Layer | Chosen tech | Why | Borrowed from |
|---|---|---|---|
| Kernel (track A) | Vendor/GKI kernel built from OEM source + Halium config fragment | Only way to run 2024-26 phones today | Halium, Ubuntu Touch |
| Kernel (track B) | Mainline/near-mainline (linux-next + device fork) | Long-term maintainability, no blobs | Nura/postmarketOS, Fairphone upstreaming |
| Vendor runtime (track A) | Halium generic system image per Android API level in an LXC container; `/vendor` untouched | Treble split already gives a stable vendor ABI | Android Treble/GSI, Halium |
| **Hardware Contract** | Varlink IDL over Unix sockets (control), fd-passing of dma-buf/PipeWire/eventfd (data), in-process module for display | Brokerless, works in early boot, introspectable, trivial to mock | OpenHarmony HDI (IDL + versioned packages), Treble (VINTF matrix, frozen stable AIDL), Fuchsia (capability routing, `@available`) |
| Providers | One Go multi-call daemon `hwd` (+ C/C++ plugins where forced: Mir platform, audio, camera) | Solo dev is productive in Go; providers are mostly glue | hfd-service (UBports), ofono2mm (Droidian) as precedents |
| Base system | Ubuntu 26.04 LTS debs (glibc, systemd 259) assembled with mkosi into EROFS + dm-verity | libhybris needs glibc; 5-year security archive; developer's home ecosystem | Ubuntu Touch (base), Duranium (image-based pattern) |
| Boot/update | Android A/B slots, AVB with custom key where supported, RAUC 1.15 with custom bootloader backend calling `qbootctl` | One updater for both tracks; rollback is the bootloader's job | Android A/B + AVB, Duranium, RAUC |
| Compositor | Mir 2.x (MirAL); display backend = Mir graphics platform module (`gbm-kms` or hybris/hwcomposer) | Only maintained compositor core whose two backends are both under active upstream work | Ubuntu Touch/Lomiri, Canonical Mir |
| Shell/toolkit | Qt 6.11 QML shell; first-party apps in QML/JS | In-process scene graph for fluid gestures; JS-adjacent for a TS developer | Lomiri, Sailfish (lipstick) |
| Apps | Flatpak + xdg-desktop-portal with an Isthmus backend; PWAs; optional Waydroid | Existing mobile-Linux app catalogue; portals are the natural choke point above the HC | Duranium/Phosh ecosystem, Android permission UX |
| Device port | `device.toml` manifest + sysext image + boot image, checked against a compatibility matrix | Declarative, testable, CI-able | Android VINTF, OpenHarmony HCS, pmbootstrap deviceinfo |
| Conformance | `hc-vts` test suite + mock providers | Port quality becomes measurable; shell runs on a laptop | Android VTS/CTS, OpenHarmony XTS |

## 1. Hardware adaptation

**Facts that shape this (verified 2026-10-03).** Pixel kernel source now arrives via a Google Form and a Drive link, weeks late and without commit history, and device trees stopped with Android 16 (https://www.androidauthority.com/google-pixel-kernel-code-forms-3696441/). OnePlus added application-gated unlocking with quotas on ColorOS 16, China-only so far (https://www.androidauthority.com/oneplus-bootloader-unlocking-restriction-coloros-16-3587810). Fairphone is the opposite: Luca Weiss's FOSDEM 2026 talk says FP4/FP5 mainline is "mostly Works with some Partial", audio being the main pain point, FP5 daily-driver "now or hopefully soon" (https://fosdem.org/2026/schedule/event/mainline_kernel_for_fairphones_-_2026_update); by August 2026 the Fairphone (Gen. 6) had all three cameras, audio and an end-to-end IMS emergency call on mainline (https://linmob.net/weekly-update-34-2026/). On the Halium side, the Ubuntu Touch FP5 port is rated full-featured (camera, calls, fingerprint, NFC, Waydroid; VoLTE "experimental") on a 5.4 vendor kernel (https://devices.ubuntu-touch.io/device/fp5). UBports is integrating Halium 16 ports (https://phoronix.com/news/Ubuntu-Touch-Toward-26.04); Droidian 101 ships Halium 13 (https://forum.droidian.org/t/droidian-101-discussion-thread/40). Completeness of Halium 14-16 is *unverified*.

**Decision: both tracks, per device, selected by manifest.** The kernel is the hard boundary — a device boots either a vendor kernel or a mainline kernel — so a *device layer* is all-or-nothing per boot, but two device layers for the same phone can coexist and be swapped.

Track A (android-vendor), how each subsystem is reached:

- **Vendor HALs** run inside an LXC container started from a Halium-built minimal Android system image, shared by all devices at the same Android API level (`hwbase-android-33`, later `-36`). Target AIDL HALs first: stable AIDL is where new HAL interfaces have landed since Android 13/14 (camera: https://source.android.com/docs/core/camera/camera3, audio: https://source.android.com/docs/core/audio/aidl-implement). HIDL is supported only as far as existing Halium components already do.
- **Binder access** from the host: `libgbinder` (mer-hybris) today; the Rust `rsbinder` crate later. Binder itself is mainline, and the Rust driver landed in Linux 6.18 (https://phoronix.com/news/Rust-Binder-For-Linux-6.18).
- **GPU/display**: libhybris-loaded Android EGL/GLES (and Vulkan, which FuriLabs is bringing up on the FLX1 per https://linmob.net/weekly-update-23-2026/) plus hwcomposer.
- **Android base**: the vendor image the phone shipped with or was last updated to; Isthmus never rebuilds `/vendor`. Minimum supported base Android 13 (API 33); Android 16 (API 36) base as soon as Halium 16 is usable. Android 17's GKI branch is `android17-6.18` (https://source.android.com/docs/core/architecture/kernel/gki-android17-6_18-release-builds); no Halium for it exists yet.

Track B (mainline): DRM/KMS + Mesa (freedreno/turnip, panfrost/panvk), ModemManager + libqmi over QRTR, ALSA UCM + PipeWire, libcamera 0.7 with GPU soft-ISP (https://phoronix.com/news/libcamera-0.7.1-Released), IIO or Qualcomm SSC sensors (fastrpc), BlueZ on serdev HCI.

**Deliberately not done:** no generic "GSI for all Treble phones" claim. Treble makes `/vendor` stable for *Android's* framework; Halium ports still need per-device kernel work. Isthmus's generic image is generic *above the contract*, which is a narrower and honest promise.

## 2. The Hardware Contract, concretely

### 2.1 IPC decision

| Candidate | Verdict | Reason |
|---|---|---|
| **Varlink** | **Chosen for control plane** | Brokerless Unix sockets; usable before dbus-broker starts; IDL with runtime introspection; streaming replies (`more`); peer credentials for auth; systemd socket activation. systemd had 19 Varlink vs 11 D-Bus services by v257 and made `sd-varlink` public (https://lwn.net/Articles/1002398); v260 added a service registry (https://www.phoronix.com/news/systemd-260-Released). Libraries: `varlink/go`, Rust `zlink` 0.7 with IDL codegen (https://docs.rs/zlink/), Python `varlink`. |
| D-Bus | Kept only where adopted upstream APIs already use it (BlueZ, and internally to talk to oFono/ModemManager) | Broker hop, no early boot, weak versioning story; but ripping it out of BlueZ et al. is pointless |
| Binder + stable AIDL | Rejected above the contract; used below it on track A | Best versioning discipline, but tooling outside AOSP is thin, needs binderfs on dev laptops and CI, and alienates Linux-desktop contributors |
| gRPC | Rejected | HTTP/2 weight, no fd passing, no peer credentials |
| Wayland protocols | Client-facing only | Right for apps-to-compositor, wrong for daemons |
| FIDL | Rejected | Not practically usable outside Fuchsia; and Fuchsia's own driver framework "has not achieved ABI stability yet" (https://fuchsia.dev/docs/concepts/drivers/driver_framework) — a caution to keep the contract small |

**Data plane never goes through JSON.** Calls return file descriptors: dma-buf (camera frames, via PipeWire), an `eventfd`+shared-memory ring (sensor batches), evdev fds (input), PipeWire nodes (audio). **Display is not IPC at all**: it is an in-process module ABI, because libhybris must load Android EGL into the compositor process and per-frame IPC is unacceptable.

### 2.2 Capabilities

| Capability | Contract seen from above | Mainline provider | Android-vendor provider |
|---|---|---|---|
| display | Mir graphics-platform module ABI (in-process) | `mir:gbm-kms` + Mesa | UBports hybris platform for Mir 2.x → HWC2/composer3 + Android EGL |
| input | libinput/evdev (adopted) | same | same |
| telephony | `org.isthmus.hw.telephony.v1` | wraps ModemManager + `81voltd`/`imsd` | wraps oFono + `ofono-binder-plugin` (IRadio AIDL/HIDL) |
| audio | PipeWire/Pulse protocol (adopted) + `hw.audioroute.v1` (call mode, routing, HAC, volume curves) | PipeWire + ALSA UCM, q6voice | v1: PulseAudio + `pulseaudio-modules-droid`; later a PipeWire SPA plugin over the AIDL audio HAL |
| camera | PipeWire camera nodes (adopted) + `hw.camera.v1` (enumeration, still capture, capabilities) | libcamera 0.7 | `droidmedia`-based provider feeding PipeWire |
| sensors | `hw.sensors.v1` (subscribe → fd) | IIO / libssc | ISensors AIDL via binder (as `sensorfw`'s hybris plugin does) |
| power | `hw.power.v1` (battery, thermal, suspend blockers, wake reasons, performance hints) | `power_supply`, thermal zones, s2idle | same sysfs + Android Power HAL hints + wakelock sysfs |
| bluetooth | BlueZ D-Bus (adopted) | serdev HCI | `bluebinder` (IBluetoothHci → VHCI) |
| wifi | nl80211 via iwd/NetworkManager (adopted) | ath1xk etc. | vendor driver, same nl80211 |
| location | `hw.location.v1` | ModemManager QMI LOC / gnss-share | IGnss AIDL |
| nfc | `hw.nfc.v1` (thin) | kernel NCI + neard | Sailfish `nfcd` binder plugin |
| biometric | `hw.biometric.v1` | usually absent (`NotSupported`) | IFingerprint AIDL (as UBports `biometryd`) |
| feedback | `hw.feedback.v1` (haptics, LEDs) | ff evdev, LED class | vibrator/lights AIDL (UBports `hfd-service` is the precedent) |
| keystore | `hw.keystore.v1` (optional, phase 3) | software / OP-TEE if present | KeyMint AIDL |

Sample (abridged):

```
interface org.isthmus.hw.telephony.v1
type Info (minor: int, backend: string, capabilities: []string)
type Call (id: string, state: (dialing, alerting, incoming, active, held, ended),
           number: ?string, ims: bool, emergency: bool)
method GetInfo() -> (info: Info)
method Dial(modem: string, number: string) -> (call: Call)
method Answer(id: string) -> ()
method Hangup(id: string) -> ()
method ActivateContext(modem: string, apn: ?string) -> (ifname: string, ip: IpConfig)
method Monitor() -> (event: Event)        # streamed with "more"
error NotSupported (capability: string)
```

### 2.3 Versioning policy (Treble + HDI + FIDL, shrunk)

1. **Major version in the interface name** (`…telephony.v1`), mirroring HDI's `ohos.hdi.foo.v1_0` packages in `drivers_interface` (https://gitcode.com/openharmony/drivers_interface).
2. **Within a major, additive only**: new methods, new nullable fields, new enum values that clients must tolerate. Every provider answers `GetInfo` with a minor number and capability strings; an absent optional method returns `NotSupported`.
3. **Frozen and hashed** like stable AIDL: released IDL lives in `hw-contract/frozen/<iface>/<minor>.varlink` with a SHA-256 in `contract.lock`; CI fails on any edit.
4. **Compatibility matrix**: OS release *N* accepts majors *N* and *N-1* of each interface. A device layer declares what it provides; `hc-check` (the `checkvintf` analogue) runs at image build and again on-device before an OTA is applied. An OS update that the installed device layer cannot satisfy is refused, not attempted.
5. **Deprecation annotations** in IDL comments (`@added 1.2 @deprecated 1.5`), FIDL-style, from which the compatibility tables are generated.
6. **Vendor extensions** live in a separate namespace (`org.isthmus.hwx.<vendor>.*`) and may never be required by the shell.

### 2.4 How a port declares its backend

```toml
[device]
codename = "fairphone-fp5"; soc = "qcm6490"
track = "android-vendor"            # or "mainline"
[android]                            # track A only
api_level = 33; hwbase = "hwbase-android-33"
[kernel]
source = "git+https://…/kernel-fairphone-fp5"; defconfig_fragment = "halium.config"
[boot]
slots = "android-ab"; slot_tool = "qbootctl"; avb_custom_key = true
[providers]
display   = { backend = "hybris-hwc", composer = "aidl-composer3" }
telephony = { backend = "ofono-binder", radio = "aidl", contract = "1.0" }
sensors   = { backend = "android-aidl", contract = "1.0" }
camera    = { backend = "droidmedia", contract = "1.0" }
biometric = { backend = "android-aidl", contract = "1.0" }
nfc       = { backend = "none" }
[vts]
waivers = ["telephony.ims.*", "camera.still.raw"]
```

A second file, `device-mainline.toml`, describes the same phone on track B. The build turns each into a signed systemd-sysext image (`device-fp5-vendor.raw`, `device-fp5-mainline.raw`) containing provider configuration, udev rules, firmware pointers and unit drop-ins, plus a boot image.

### 2.5 What the abstraction costs and what it buys

**Engineering cost (estimates for one full-time developer; double for evenings-and-weekends):**

| Item | Person-months | Notes |
|---|---|---|
| Contract design, codegen, `hwd` skeleton, mocks | 1.5 | Varlink IDL → Go/Rust/Python/QML-JS bindings |
| Telephony pair (calls, SMS, data, SIM, USSD) | 3 | Wraps two mature daemons; data-context handover to networking is the hard part |
| Power + feedback + sensors pairs | 2 | |
| Audio routing pair | 1.5 | v1 keeps PulseAudio on track A |
| Camera pair | 2-3 | Lowest-common-denominator risk highest here |
| Location, NFC, biometric | 2 | Mostly track A |
| `hc-vts` conformance suite | 1.5 | Pays for itself in port triage |
| **Total "tax" for the abstraction** | **≈ 13-15** | versus ≈ 5-6 to wire a shell directly to one track |

So the abstraction costs roughly **8-9 extra person-months up front** and, by my estimate, a 15-20% ongoing maintenance tax (each contract change touches two providers and the suite). A later PipeWire SPA plugin for the Android audio HAL would add about 3 months; whether anyone has already built one is *unknown*.

**Runtime cost (estimates; measuring them is an explicit M0 task):**

- Latency: one Varlink round trip is a Unix-socket ping-pong plus small JSON encode/decode — order of 50-150 µs on a Cortex-A78-class core, versus roughly 20-50 µs for binder and a few hundred µs for brokered D-Bus. Because v1 providers wrap existing daemons, a call such as `Dial` pays one Varlink hop plus one D-Bus hop: about 1 ms added to an operation that takes seconds.
- Rate: control-plane traffic is single-digit calls per second at most; CPU overhead is far below 0.1%.
- Memory: one `hwd` multi-call process hosting all interfaces ≈ 25-35 MB RSS; split per capability for isolation it is ≈ 12-20 MB each. Rarely used interfaces (NFC, biometric) are socket-activated and exit on idle.
- Standby: the real danger is wakeups, not bytes. Providers must be purely event-driven; `hc-vts` enforces a budget of under one wakeup per second per provider at idle.
- Display and data plane: zero added overhead (in-process module; fds passed straight through).

**What it buys:**

1. One OS image and one shell codebase for both tracks — the alternative is what the ecosystem lives with now (ofono2mm, parallel shells).
2. **In-place track migration**: swap the device layer and boot image, keep OS, apps and data.
3. Mock providers, so the full shell runs on a laptop and in CI with scripted events ("incoming call", "battery 4%", "SIM removed").
4. A conformance suite that turns "does the port work?" into a number, and auto-generates the device status page.
5. One enforcement point for privacy switches and permission checks (section 8).
6. Insulation from upstream churn: the 2026 postmarketOS → Nura rename, Mir 1→2, oFono vs ModemManager wars stop at the provider.

**When it is not worth it:** if only one track ever ships. The M1 milestone exists to find that out within six to seven months.

## 3. Base system

- **Distro base: Ubuntu 26.04 LTS** arm64 packages (released 2026-04-23 with systemd 259, security support to 2031: https://computingforgeeks.com/ubuntu-2604-lts-features/). glibc is non-negotiable because libhybris and the Halium userspace assume it; this rules out an Alpine/musl base regardless of how good Nura's tooling is. Ubuntu Touch is itself moving to a 26.04 base, so adaptation packages can be shared.
- **Not Ubuntu Core/snapd for the base.** It is a coherent immutable design the developer knows, but it couples updates and apps to one store and its Android-bootloader support status in 2026 is *unverified*. Snap can be offered later as an optional app format.
- **Image build: mkosi** producing an EROFS `/usr` with dm-verity; `/etc` and `/var` on encrypted userdata. No package manager on the device. This is the Duranium pattern (systemd-repart, verity, UKI, EROFS, Flatpak: https://postmarketos.org/blog/2026/03/17/introducing-duranium/, now redirecting to nura.eco after the rename: https://itsfoss.com/news/postmarketos-nura-rebranding/), re-hosted on Ubuntu debs.
- **Init: systemd 259.** libc: glibc (bionic only inside the vendor container).
- **OS-specific packages** live in one deb archive built with `sbuild` in LXD containers and published from CI; the image is the only shipped artifact.

## 4. Boot, kernel, updates

Four artifacts per release: `os-<ver>.erofs` (generic, identical everywhere), `hwbase-android-<api>.raw` (track A only), `device-<codename>-<track>.raw` (sysext), `boot-<codename>-<track>.img`.

- **Boot chain, both tracks, on Android bootloaders:** ABL → `boot.img` (header v4; kernel + initramfs; verity root hashes on the signed command line) → initramfs maps the OS image from the active slot's logical partition in `super`, merges the device sysext, switches root. Keeping ABL on track B too (rather than chain-loading U-Boot as UEFI, which Duranium does) means one slot mechanism for both tracks, which is what makes in-place migration simple.
- **A/B and rollback:** Android slot metadata is the source of truth. A unit ordered after `boot-complete.target` marks the slot good with `qbootctl` (https://github.com/linux-msm/qbootctl), which exists precisely because Qualcomm bootloaders fall back when nobody sets the flag. Non-Qualcomm devices need an equivalent; MediaTek/Tensor tools are *unverified*.
- **Updater: RAUC 1.15** (https://rauc.readthedocs.io/) with a custom bootloader backend script wrapping the slot tool, signed bundles and adaptive (block-hash-index) delta downloads (https://pengutronix.de/en/blog/2025-04-09-rauc-v1-14-released.html). One updater, both tracks. A small Go service `updated` adds the `hc-check` gate, scheduling and the shell-facing API.
- **Verified boot:** boot image and vbmeta signed with the project's AVB key. Where the bootloader honours `avb_custom_key` (Pixels; Fairphone 4/5 per community guides, with real bricking risk if done wrong: https://forum.fairphone.com/t/guide-to-bootloader-and-bricking-2025/121352/3) the bootloader can be relocked into the "yellow" state. Elsewhere the device stays unlocked and the OS says so plainly in Settings.
- **Track migration:** an update bundle carrying a different device sysext and boot image for the inactive slot. If the new track fails to reach `boot-complete`, the bootloader returns to the old slot.

## 5. Graphics and compositor

Evaluated on merit, including the earlier Qt Wayland Compositor suggestion:

| Option | Mainline backend | Vendor backend | Assessment |
|---|---|---|---|
| **Mir 2.x** | `gbm-kms` (Canonical, monthly releases; 2.29 upcoming in Aug 2026: https://discourse.ubuntu.com/t/mir-office-hours-2026-08-26-15-15utc/86410) | UBports hybris platform; "first successes with new platform API" in Feb 2026 (https://discourse.ubuntu.com/t/mir-office-hours-2026-02-25-16-15utc/77316), Mir 2 transition planned for H2 2026 (https://pretalx.coscup.org/coscup-2026/talk/8UMS73/) | **Chosen.** Its loadable graphics-platform ABI *is* the display half of the contract, and other people maintain both halves |
| wlroots 0.20 | upstream DRM | Droidian's hwcomposer fork, still on 0.17.4 (https://github.com/droidian-images/droidian/releases) | Fallback. Fork is three releases behind |
| Qt Wayland Compositor (6.11) | eglfs-kms | hwcomposer QPA plugin; Qt 6 port status *unverified* | Viable but thinner protocol coverage and no one else pushing the vendor backend forward |
| Smithay / cosmic-comp | DRM | none found | Would mean writing a hwcomposer backend alone: 3+ months of risk |

GPU drivers are whatever the track gives: Mesa on B, vendor GLES/Vulkan through libhybris on A. Clients on track A need the libhybris Wayland-EGL platform (the "client wayland platform for libhybris" flagged as outstanding in the February Mir notes); inside Flatpak this has to be shipped as a GL runtime extension, the approach Droidian has used (*unverified* for current releases).

**Risk accepted:** the Mir 2 hybris platform is not yet in a shipped Ubuntu Touch release. Decision gate at month 3: if it cannot drive the M1 device, switch M1 to the Droidian wlroots fork and revisit.

## 6. Shell, toolkit, and the differentiator

- **Shell:** Qt 6.11 QML, drawn in the compositor process through `qtmir` (UBports' Qt-on-Mir bridge, whose Qt 6 port is in progress — Lomiri's Qt 6 migration was reported at roughly 75% overall in 2026, per the COSCUP talk abstract cited above). In-process QML is what makes Lomiri's and Sailfish's gesture animations fluid; an out-of-process layer-shell shell (the Phosh model) is the fallback if `qtmir` on Qt 6 is not ready. QML's JavaScript core is the least-foreign native option for a TypeScript developer. This reuses Lomiri's *plumbing*, not its shell.
- **Not chosen:** GTK4/libadwaita + phoc (fine stack, but its vendor-track compositor is the stale fork above); Flutter shell (no maintained compositor integration; "Denial" is an experiment); web-tech shell (performance and memory on mid-range devices).
- **Differentiator — "the honest phone":**
  1. *Hardware page.* Settings shows every capability, which provider serves it, whether it is open or blob-backed, its contract version and its `hc-vts` score. No other mobile OS exposes this.
  2. *Migration, not abandonment.* When the mainline device layer for your phone passes the conformance bar, the updater offers it. Support life is decoupled from the vendor's Android schedule.
  3. *Switches that mean something.* Camera, microphone, modem, location toggles are enforced inside the provider, below every app and below the shell.
  The interaction model itself stays conservative: edge gestures and convergence in the Lomiri tradition the user already lives with.

## 7. App model

- **Packaging: Flatpak** (primary), with Flathub's existing mobile-adapted GTK and Qt apps available from day one. No click, no OCI. Snap optional later.
- **Sandbox and permissions:** bubblewrap + portals. `xdg-desktop-portal-isthmus` (Go) implements the prompts and is the *only* app-reachable path to hardware: Camera → PipeWire node from `hw.camera`; Location → `hw.location`; new portals for telephony-adjacent features (dial intent, SMS compose) rather than raw modem access. HC sockets under `/run/isthmus/hw/` are mode 0660 for a system group; apps never see them.
- **Native SDK:** QML/JS component kit shared with the shell; `isthmus dev` scaffolds, runs in the simulator, and packages a Flatpak.
- **Web/PWA:** installable web apps in a per-app profile of a system web runtime (QtWebEngine 6.11), each a sandboxed Flatpak instance.
- **Flutter:** supported as ordinary Wayland clients in Flatpak; not first-party.
- **Android compatibility:** Waydroid, optional and off by default. Upstream still ships an Android 13 (LineageOS 20) image, with initial Android 16 image support in 1.6.3 (secondary source: https://tech-insider.org/waydroid-setup-linux-steam-deck-2026/); Droidian ships Halium 13 Waydroid vendor images; the UT FP5 port lists Waydroid as working. It is a bridge for banking-free essentials, not a pillar — Play Integrity will fail.

## 8. Telephony, audio, camera, sensors, power

- **Telephony.** Track A: oFono with the Sailfish binder plugin stack (`ofono-binder-plugin`, `libgbinder-radio`, AIDL radio support: https://forum.sailfishos.org/t/sailfish-community-news-29th-august-2024-c2-update/19793/7). Track B: ModemManager. **VoLTE is the weakest point on both tracks**: Jolla's Qualcomm IMS extension is proprietary; UBports reached first VoLTE calls on a Pixel 3a only in April 2026 (https://ubports.com/blog/ubports-news-1/ubuntu-touch-q-a-187-april-4th-3994); mainline relies on `81voltd` (https://packages.debian.org/sid/81voltd) and the reverse-engineered `imsd` (https://zff.dev/flamingradian/imsd), with NLnet funding earlier work (https://nlnet.nl/project/VoLTE-Qualcom/). The contract exposes IMS state as a capability so the shell can say "calls on this network need VoLTE, which this port lacks" instead of failing silently.
- **Audio.** Apps see the PulseAudio/PipeWire protocols on both tracks. v1 on track A runs PulseAudio with `pulseaudio-modules-droid` (https://github.com/mer-hybris/pulseaudio-modules-droid) because it works today; PipeWire handles video only. `hw.audioroute` hides call-mode switching, which is where the two tracks differ most.
- **Camera.** PipeWire nodes for preview/video on both tracks; `hw.camera` for stills. Track A gets vendor ISP quality; track B gets libcamera soft-ISP quality, which the FOSDEM talk itself says still needs tuning and autofocus work. The contract reports quality-relevant capabilities rather than pretending parity.
- **Sensors.** Subscribe-and-stream with batching parameters, so the provider can use hardware FIFOs on both tracks and the application processor can stay asleep.
- **Power and standby.** A single `powerd` (above the contract) owns opportunistic suspend: screen off and no blockers → suspend within seconds; coalesced RTC wake alarms; push via one UnifiedPush distributor connection. `hw.power` supplies blockers, wake reasons after each resume (feeding a per-app "battery blame" view) and vendor performance hints. Targets, not facts: ≤ 1%/h idle drain on track A by beta and ≤ 1.5%/h on track B, tightening to 0.5%/h. I found no published 2026 standby figures for FP5 on mainline (*unknown*); measuring both tracks on the same phone is one of the more valuable by-products of M2.

## 9. Security and privacy

- **Integrity:** AVB-signed boot image → dm-verity OS image → dm-verity sysext and hwbase images. No writable code outside Flatpak.
- **Data at rest:** LUKS2 on userdata. On track A the key is wrapped by KeyMint through `hw.keystore` (hardware-throttled); on track B it is passphrase-only Argon2id until a TEE path exists — a real, stated regression of mainline today.
- **Blob containment:** the vendor container is the largest untrusted component. It gets its own network namespace with only the IMS/RIL daemons allowed to reach rmnet interfaces, a seccomp profile, and no access to userdata. This limits, but does not remove, trust in vendor code; the modem and TrustZone remain opaque on both tracks.
- **Provider hardening:** systemd sandboxing (`ProtectSystem=strict`, `DeviceAllow`, `SystemCallFilter`, `PrivateNetwork` where possible) plus AppArmor profiles, since the base is Ubuntu.
- **Authorization:** providers identify callers by `SO_PEERCRED` → cgroup → unit or Flatpak app ID and consult a static policy table. No polkit.
- **Privacy switches** enforced in providers; indicators driven by provider events, so no app can use the camera without the indicator.

## 10. Developer experience and build infrastructure

- **Repos:** `hw-contract` (IDL, frozen versions, bindings, mocks, `hc-vts`), `hwd`, `os` (mkosi), `shell`, `sdk`, one `device-<codename>` repo per port.
- **CLI `isthmus` (Go):** `port new|check|build`, `image build --device fp5 --track mainline`, `flash`, `vts run`, `sim`.
- **Simulator:** `isthmus sim` runs Mir nested on the desktop session with the real shell and mock providers, scriptable from Python or TypeScript.
- **Emulator:** the same mkosi image boots under QEMU aarch64 `virt` with virtio-gpu and a "virt" device layer; CI runs `hc-vts` and shell smoke tests there on hosted arm64 runners.
- **Hardware CI (phase 2+):** two phones on a USB-controlled rig running flash → boot → `hc-vts` nightly, following Nura's hardware-testing automation mentioned in the FOSDEM 2026 slides.
- **Porting levels:** Bronze/Silver/Gold from the VTS pass rate, with waivers listed in the manifest. A port from an existing Halium adaptation should reach Bronze in days, because the provider code is generic and only configuration differs.

## 11. Borrowed and deliberately not borrowed

| Reference | Borrowed | Not borrowed, and why |
|---|---|---|
| **Nura/postmarketOS** | Mainline kernels and device knowledge; Duranium's image-based pattern; `qbootctl`; hardware CI idea | Alpine/musl base (libhybris); pmbootstrap; U-Boot-as-UEFI chain-load (would split the slot mechanism) |
| **Ubuntu Touch/Lomiri** | Mir + hybris platform, `qtmir`, `hfd-service`/`biometryd` as provider precedents, Ubuntu base, edge-gesture UX | Lomiri shell and click packages (this is not a fork); the oFono-only assumption |
| **Halium/Droidian/FuriOS** | Halium system images, LXC vendor container, libhybris, bluebinder, droidmedia; ofono2mm as proof that shims work | Shim-per-upstream-API as the architecture — it is the ad-hoc version of what the contract formalises; Phosh on a stale wlroots fork |
| **OpenHarmony** | HDI: IDL files in one repo, versioned packages, generated stubs; HCS-style declarative device config; XTS conformance | HDF's kernel-side driver model (forfeits every mainline Linux driver); ArkUI/ArkTS; GN/hb; distributed soft-bus. OpenHarmony 6.x shipped May 2026 (https://www.ithome.com/0/956/518.htm) but its phone hardware story is Huawei-centric |
| **Android** | Treble split, VINTF-style matrix, frozen-and-hashed stable interfaces, A/B slots, AVB, VTS, permission UX | Binder as the OS-side IPC; AOSP/Soong build; ART/framework; SELinux policy at Android's scale |
| **Fuchsia** | Capability routing by manifest; `@available` deprecation annotations; "small stable surface" discipline | FIDL and Zircon; the ambition of ABI-stable *drivers* |

## 12. Roadmap (1 developer, growing to 3)

| Phase | Months | Deliverable |
|---|---|---|
| P0 | 0-2 | Contract v0 (power, feedback, sensors, telephony); `hwd` skeleton; mocks; `isthmus sim` with a stub QML shell; IPC benchmark on a real phone |
| **M1 — thesis proof** | **2-7** | **One OS image with one SHA-256 boots on the OnePlus 6 the user already owns, under two device layers: sdm845 mainline, and the existing Halium adaptation (its Ubuntu Touch port is focal-only today: https://devices.ubuntu-touch.io/device/enchilada). Both pass the same `hc-vts` subset: compositor at 60 fps, touch, voice call in and out, SMS, mobile data, accelerometer/proximity/light, battery state, suspend with wake on incoming call, vibration. A minimal shell (lock screen, dialer, messages, Hardware page) runs unmodified on both.** No camera, VoLTE or Bluetooth yet |
| P2 | 8-14 | Fairphone 5 on both tracks; call audio, camera, Wi-Fi, Bluetooth, location; RAUC A/B with rollback; Flatpak + portals; contract 1.0 frozen; public alpha and porting guide |
| P3 | 15-24 | Halium 16 base and a 2025-26 device (Fairphone Gen. 6 first); VoLTE where feasible; verified boot with custom keys; Waydroid; daily-driver beta on FP5; first in-place track migration |
| P4 | 24-36 | Direct-binder providers in Rust for hot paths; PipeWire audio on track A; NFC/fingerprint polish; contributor-maintained ports; contract v2 planning |

**Kill criteria at M1:** if the two providers for any core capability cannot be hidden behind one interface without the shell branching on track, the thesis is wrong — collapse to a single track and keep the mocks and test suite, which are valuable regardless.

## 13. Top risks and mitigations

1. **Scope versus one person.** A contract, two providers each, a shell and a distro. *Mitigation:* adopt-don't-invent; wrap existing daemons; two devices only until 1.0; hard M1 gate.
2. **Leaky, lowest-common-denominator contract** (camera quality, VoLTE, call audio). *Mitigation:* capability flags and optional methods; control plane only; vendor-extension namespace; accept visible differences and surface them in the Hardware page.
3. **Dependence on unfinished upstream work** (Mir 2 hybris platform, Qt 6 `qtmir`, Halium 16). *Mitigation:* month-3 gate with the Droidian wlroots fork and an out-of-process shell as fallbacks; contribute upstream rather than fork.
4. **Hardware access closing** (Pixel source gating, OnePlus unlock policy). *Mitigation:* Fairphone-first; a published device-eligibility policy (unlockable, kernel source, custom AVB key); watch the GrapheneOS-Motorola devices expected in 2027 (https://www.androidauthority.com/grapheneos-motorola-partnership-announced-3645710) as a possible second vendor.
5. **Vendor ABI drift and proprietary IMS.** *Mitigation:* per-API-level hwbase images; AIDL version negotiation in providers; VoLTE treated as a capability, not a promise.
6. **Standby regressions from extra daemons.** *Mitigation:* single `hwd` process, socket activation, wakeup budget enforced in `hc-vts`.
7. **Security of the vendor container.** *Mitigation:* namespace, seccomp, network policy; honest documentation of what cannot be contained.
8. **Yet another mobile Linux OS.** *Mitigation:* publish `hw-contract`, mocks and `hc-vts` as standalone projects that Nura, UBports and Droidian could adopt without adopting Isthmus; that is also the most plausible way to attract contributors and an NLnet-style grant.
9. **Bus factor and no funding.** *Mitigation:* Go and QML lower the contributor barrier; conformance suite makes drive-by ports reviewable; apply for grants once M1 is demonstrable.
