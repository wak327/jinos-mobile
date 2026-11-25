# Android internals worth borrowing, and the 2025-2026 AOSP/Pixel changes

Research date: 2026-10-02. Everything about "current status" below was checked against sources dated 2025-2026 (see section 7). Where a claim rests on general knowledge or could not be verified, it is marked **[unverified]**.

Framing: the target OS is a glibc/Linux userspace (Go, Python, TypeScript, snap/LXD background) that must reuse Android vendor firmware on current phones. Android is therefore relevant in two ways: as the *substrate* whose vendor-side contracts (Treble/VINTF, AIDL HALs, GKI, AVB) the new OS must speak, and as a *design reference* for the system layer above it (sandboxing, power, updates, graphics).

---

## 1. Architecture (layers, key components, how hardware is reached)

**Kernel.** Devices launching with Android 12+ on kernel 5.10+ must ship the Generic Kernel Image (GKI): one binary per architecture per LTS (branches `android14-6.1`, `android15-6.6`, `android16-6.12`), built from the Android Common Kernel, with all SoC/board code moved into loadable vendor modules behind a frozen Kernel Module Interface (KMI). The KMI is binary-stable within a branch, so the GKI kernel and vendor modules update independently [S13].

**Binder.** Android's IPC is a kernel driver with three device nodes: `/dev/binder` (framework/apps, AIDL), `/dev/hwbinder` (HIDL, legacy), `/dev/vndbinder` (vendor-to-vendor AIDL), each with its own service manager; Android 8 added single-copy scatter-gather and fine-grained locking with real-time priority inheritance [S14]. A Rust rewrite of the driver was merged upstream in Linux 6.18, coexisting with the C driver for now [S15]. Binder gives the system layer kernel-attested caller UID/PID, reference-counted object handles (capabilities), file-descriptor passing and death notifications **[general knowledge]**; that is why it, not D-Bus, underpins both the app framework and the vendor boundary.

**Treble / VINTF.** Since Android 8 the OS is split into a framework half (`system`) and a vendor half (`vendor`, `odm`) that talk only over versioned HAL interfaces. Four VINTF objects govern compatibility: device manifest, framework manifest, framework compatibility matrix (FCM) and device compatibility matrix; they are checked at build, OTA and boot time, and the FCM also encodes kernel requirements [S16]. HAL interfaces moved from HIDL to **stable AIDL** (`@VintfStability`, `stability: "vintf"`) beginning Android 11; HIDL has been deprecated since Android 13 and new HAL APIs from Android 14 onward are AIDL-only (Audio became AIDL in 14) [S17]. The VNDK (framework libs vendors may link) is deprecated for vendor partitions targeting Android 15: vendors must bundle everything except the LL-NDK (libc, libm, libEGL, libvulkan...) [S18]. UBports porters confirm that what matters to Halium is the vendor's VNDK/vendor API level, not the marketing Android version; e.g. Fairphone 5 on Android 15 still exposes VNDK 30 [S19].

**SELinux.** Mandatory since Android 5; policy is built separately for platform and vendor since Android 8: `system/sepolicy/public` is the stable "sepolicy API" vendors may reference, `private` is framework-internal, vendor policy lives in `BOARD_SEPOLICY_DIRS`, and per-version *mapping files* keep older vendor policy compatible with newer platform types. Policy is compiled to CIL, precompiled to `/vendor/etc/selinux/precompiled_sepolicy` with a SHA256 check; `init` falls back to on-device compilation on mismatch [S21]. Android deliberately uses only type enforcement: no SELinux users, roles, MLS or booleans [S22].

**App sandbox.** Each app gets its own Linux UID and process; since Android 9 every nonprivileged app (targetSdk >= 28) also gets its own SELinux domain; seccomp-bpf filters (Android 8) restrict syscalls; app home directories became mode 700 in Android 6; scoped storage (Android 10) replaces raw `/sdcard` access with MediaStore and per-package directories [S23]. Runtime permissions and the new media-type permissions (`READ_MEDIA_IMAGES` etc.) sit on top.

**Boot and updates.** AVB 2.0 signs a `vbmeta` struct holding hash descriptors (boot) and hashtree/dm-verity descriptors (system, vendor), with chained partitions for delegation and per-partition rollback indexes stored in tamper-evident storage (RPMB via the TEE). Boot states: GREEN (locked, OEM key), YELLOW (locked, *user-settable custom key*), ORANGE (unlocked), RED (verification failed) [S24][S25][S26]. Storage uses a single `super` partition with `liblp` metadata and `dm-linear` logical partitions (dynamic partitions) [S27]. Updates are Virtual A/B: instead of duplicating all partitions, changes are snapshotted to `/data`; Android 12 added a custom COW format with Copy/Replace/Zero/XOR ops (45-55% smaller), Android 13 moved merging fully to userspace via `snapuserd` + `dm-user`; Virtual A/B is a GMS requirement for devices launching with Android 11+, and non-A/B is deprecated in Android 15 [S28]. Low-level modules (ART, media, Bluetooth, tzdata, RKP, config infrastructure...) ship as **APEX** files: a zip containing `apex_manifest`, an ext4 `apex_payload.img` under dm-verity, and a public key, loop-mounted at `/apex/name@version` by `apexd`, with staging and rollback integrated with Virtual A/B [S29]. There are about 30 Mainline modules (APEX or APK) updated via Google Play system updates or partner OTA [S30].

**Graphics.** Apps draw into BufferQueue/SurfaceControl layers; SurfaceFlinger wakes on VSYNC, collects latest buffers, asks the Hardware Composer HAL (HWC, now AIDL) via `validateDisplay`/`presentDisplay` which layers it can composite in display hardware (overlay planes), GPU-composites the rest into a client target, and passes everything with sync fences; Gralloc/IMapper allocates buffers by usage flags [S31][S32].

**Runtime.** ART executes DEX with a hybrid interpreter/JIT/profile-guided AOT (`dex2oat`), a mostly-concurrent copying GC, and has been an updatable Mainline APEX since Android 12 [S33]. Android 17 adds a generational tweak that reclaims short-lived objects without a full heap scan [S10].

**Power.** `PowerManager` wakelocks in userspace map onto kernel wakeup sources; the device uses opportunistic autosleep (`/sys/power/autosleep`, `wakeup_count`) gated by the `SystemSuspend` service; vendor tuning goes through the AIDL `IPower` HAL (hints/boost) [S34]. Above that, Doze cuts network, ignores wakelocks, defers alarms/jobs/syncs and batches them into shrinking maintenance windows; App Standby buckets throttle idle apps; `JobScheduler` is the sanctioned background-work API, and FCM high-priority pushes are the sanctioned wake-up path [S35]. Android 16 adjusts job quota by standby bucket and adds `getPendingJobReasons()` introspection [S8].

**Virtualization.** The Android Virtualization Framework runs protected VMs on pKVM with `crosvm` (Rust VMM), a minimal guest OS (Microdroid) and a `VirtualizationService`; Android 16 ships a Debian "Terminal" app on it (arm64 only) [S36][S37].

---

## 2. What it does well

1. **A contractual vendor boundary.** VINTF manifests plus stable AIDL make "does framework X run on vendor Y" a checkable question at build/OTA/boot [S16]. This is what lets GSI images boot on arbitrary Treble devices and is the single most important enabler for any alternative OS on modern phones.
2. **GKI/KMI.** Moving SoC code into modules behind a frozen ABI means a third party can rebuild the *generic* kernel from source while keeping vendor `.ko` blobs, and LTS security fixes propagate without per-device backports [S13]. GrapheneOS tracks "the latest GKI LTS branch" exactly this way [S40].
3. **Binder as a capability system.** Kernel-mediated identity, object handles and death notifications give you authorization and lifecycle for free; it now has a memory-safe driver upstream [S14][S15].
4. **Fail-safe updates.** Virtual A/B + dynamic partitions + AVB rollback indexes + APEX staging give atomic, rollback-able, space-efficient updates of the OS and of individual low-level modules [S27][S28][S29].
5. **Verified boot with a user-settable root of trust.** The YELLOW state is the only widely deployed design that lets a third-party OS keep the bootloader *locked* [S25][S26]; it is also what GrapheneOS's attestation story depends on [S4].
6. **Layered least privilege.** UID-per-app, SELinux-domain-per-app, seccomp, private data dirs and scoped storage compose so that "compromising the sandbox requires breaking Linux kernel security" [S23].
7. **Power as a platform concern.** Doze/App Standby/JobScheduler shift the battery problem from "every app behaves" to "the OS enforces batching" [S35]. The kernel-side pieces (wakeup sources, autosleep, `wakeup_count`) are upstream Linux.
8. **Memory safety at scale.** Memory-safety bugs fell below 20% of Android vulnerabilities in 2025; Rust code showed roughly 1000x lower memory-safety vulnerability density, 4x lower rollback rate and 25% shorter reviews than C++, and Android now ships a production Rust kernel driver on 6.12 [S20]. For a from-scratch system layer this is the strongest available evidence for Rust (or a GC language) over C/C++.

---

## 3. What it does badly / lessons learned

1. **Openness is a policy, not a property.** AOSP is Apache-2.0, but Android 16 (June 2025) shipped without Pixel device trees or driver binaries and with squashed kernel history; Google's stated reason was moving the reference target to the Cuttlefish virtual device [S1][S2]. Since January 2026 AOSP source drops are twice yearly (Q2/Q4) instead of quarterly [S6]. As of August 2026, Pixel kernel source is obtained via a Google Form and a history-stripped tarball delivered by Drive, "what previously took hours can now take weeks" (GrapheneOS) [S3]. GrapheneOS attributes the shift to Google treating alternative Android platforms as competitors and notes that "OEM partner access" is restricted to commercial vendors [S41]. Lesson: never let your project's viability depend on a single upstream's goodwill; design for *reverse-engineering from factory images* (GrapheneOS rewrote `adevtool` to generate device support "without any need for device trees" and used it to bring up Pixel 10) [S40][S42].
2. **Attestation became a gate on the app ecosystem.** Since May 2025, Play Integrity's `MEETS_DEVICE_INTEGRITY` requires a locked bootloader *and* a Google-certified OEM image, hardware-attested; custom ROMs get at most `MEETS_BASIC_INTEGRITY`; `MEETS_STRONG_INTEGRITY` additionally requires security patches within a year [S5]. Google could whitelist alternative OS keys through the same hardware key-attestation mechanism but does not [S4]. Separately, developer identity verification for *all* app installs on certified devices started enforcement on 30 Sept 2026 in Brazil, Indonesia, Singapore and Thailand, global in 2027; it explicitly does not cover uncertified devices or ADB [S7][S43]. A new Linux phone OS will never be "certified", so banking, ticketing, and some government apps that insist on device integrity will not work in any Android compatibility layer; this is an ecosystem risk, not a technical bug.
3. **Treble is leaky in practice.** OEMs still ship vendor images pinned to old vendor API levels (FP5: VNDK 30 under Android 15) [S19], vendor HALs assume Android's SELinux labels and `servicemanager`, and camera/graphics stacks remain the hardest to reuse. VNDK deprecation (Android 15 vendor API) means vendor partitions now carry their own copies of former framework libs [S18], which changes what libhybris finds on disk.
4. **The update machinery is heavy.** Virtual A/B needs dynamic partitions, `dm-user`, `snapuserd`, `update_engine`, and OTA payload tooling; APEX needs `apexd` early in boot and dm-verity-capable kernels [S28][S29]. Most of that complexity exists to serve OEM factories and Google Play delivery, not a community distro.
5. **Power management is adversarial.** Doze works because Google can police exemptions through Play policy and route wakeups through FCM [S35]. A community OS has neither lever; copying Doze without a central push service produces broken messaging apps.
6. **Complexity of the build.** A full AOSP build is enormous and most Mainline modules cannot be cherry-picked without the AOSP build graph [S30]. Expect to extract *protocols and formats*, not drop-in binaries.
7. **Hardware-locked OEM relationships.** GrapheneOS's first non-Pixel OEM (Motorola, announced 2 March 2026, devices in 2027) only happened for flagships that meet "expected updates and hardware memory tagging" requirements and a seven-year update commitment [S44][S45][S46]. Fairphone's unlock still requires an OEM-issued code [S47], and support for relocking Fairphone 5 with a custom AVB key is **[unverified]** in this research.

---

## 4. Current status as of 2026-10-02

- **Android 17** (API 37, codename Cinnamon Bun) released 16 June 2026; Q2 major + Q4 minor SDK release model; Samsung Galaxy Z Fold 8 / Flip 8 launched on it. Notable: session-scoped contact and location access, local-network permission, App Lock, EyeDropper API, VVC decoding, orientation/resizability restrictions ignored, ML-DSA post-quantum keys, GC that reclaims young objects without full-heap scans [S9][S10].
- **Android 16** (June 2025): 16 KB page-size compatibility mode; Play requires 16 KB support for new apps from 1 Nov 2025 [S8][S11]; GPU IOCTL filtering via SEPolicy, Keystore key-sharing API, local network permission, adaptive-refresh-rate APIs, JobScheduler quota by standby bucket, ADPF CPU/GPU headroom, APV codec, Linux Terminal app on AVF [S8][S37].
- **Android 15** (2024): 16 KB page support, Private Space, non-A/B deprecated, VNDK deprecated for vendor API 202404+, TLS 1.0/1.1 blocked, OS-level app archiving, ANGLE (GLES on Vulkan) [S12][S18][S28].
- **AOSP cadence**: Q2 and Q4 source drops only, from 2026; `android-latest-release` manifest points at `android17-release` [S6][S9].
- **Pixel openness**: no device trees/driver binaries since Android 16 [S1][S2]; kernel source behind a request form since Aug 2026 [S3]. GrapheneOS adapted via automated device support (`adevtool`) in release 2025111800 (first stable Android 16 QPR1 build) [S40]; Pixel 10 support followed in early 2026 per forum thread titles **[date from search index; the forum page did not render]** [S42].
- **GrapheneOS + Motorola**: long-term partnership announced at MWC, 2 March 2026; first compatible flagships (Signature, razr fold/ultra class) in 2027; "the same GrapheneOS as on Pixels," no bloatware; some GrapheneOS features flowing into Motorola's own OS [S44][S45][S46].
- **Play Integrity**: hardware-backed verdict definitions in force for all developers since May 2025 [S5]. GrapheneOS's guidance to developers: use hardware key attestation and accept `verifiedBootState == SelfSigned` when `verifiedBootKey` matches keys published at grapheneos.org/attestation.json [S4].
- **Developer verification**: enforcement started 30 Sept 2026 in four countries; F-Droid 2.0 shipped 24 Sept 2026 and, with EFF/FSFE/SFC, calls the policy existential [S43]. Certified devices only [S7].
- **Rust**: Rust Binder driver in Linux 6.18 [S15]; <20% memory-safety share in Android 2025 [S20].
- **Halium/libhybris**: active (hybris-patches, libhybris, android_device_halium_halium_arm64, droidmedia all updated Aug-Sept 2026) [S38]; Ubuntu Touch 24.04-2.0 shipped with partial Vulkan and Widevine; Phoronix reports UBports work on "Halium 16"-based ports **[Phoronix page returned 403 on fetch; the exact Android base of the newest Halium generation is unverified here]** [S39]. UBports porters state Halium porting notes for Android 9 "are mostly (excluding GKI) the same for even the latest version (currently 14)" [S19].
- **16 KB pages**: an increasing share of new arm64 vendor kernels will be 16 KB; any glibc userspace you ship must be 16 KB-clean (ELF segment alignment) [S11].

---

## 5. Borrowable ideas for a new OS

Legend: **CODE** = reusable as code; **PATTERN** = design to imitate; license in brackets.

**Reach the hardware**
- **Binder + stable AIDL, directly from glibc** (CODE, kernel GPLv2; `libbinder`/`aidl` compiler Apache-2.0). Because AIDL HALs are kernel IPC with a stable wire format over `/dev/binder` or `/dev/vndbinder`, a native Linux daemon can talk to vendor HAL services (HWC3, Audio, Radio, Camera provider, Sensors, Power, Vibrator, Gnss, Thermal, Health...) without bionic in-process, provided it speaks Parcel and registers/looks up services through a servicemanager. AOSP's `libbinder_rs` (Rust) and `libbinder_ndk` are Apache-2.0 [S14]. A pure-Rust binder crate independent of AOSP exists (`rsbinder`) **[maturity unverified]**; nothing comparable for Go is known **[unknown]**. Only legacy HIDL/hwbinder and in-process HALs (Gralloc mapper, GLES/Vulkan ICDs, camera pipeline internals) still need libhybris.
- **libhybris / Halium container** (CODE, libhybris Apache-2.0; Halium repos mixed Apache/GPL). Keep the Android LXC container for HIDL-era and in-process pieces, run the vendor's GKI + modules unchanged, and move new system services onto direct AIDL over Binder as device vendor API levels rise [S38][S19].
- **GKI rebuild strategy** (PATTERN). Pin to the device's ACK branch (e.g. `android15-6.6`), rebuild only the generic kernel with the configs your userspace needs *inside KMI constraints* (binderfs, cgroup v2 freezer, netfilter, SysV IPC is classically disabled in Android kernels and needed by desktop Linux software **[verify against the current GKI defconfig]**), and keep the vendor `.ko` blobs [S13].
- **VINTF manifests as your compatibility database** (PATTERN; parser is Apache-2.0 in `system/libvintf`). Read the device manifest and FCM at port time to generate which HAL versions you must support, and refuse OTAs that would break them [S16].
- **Treat the vendor API level, not the Android version, as the port key** (PATTERN) [S19].

**Boot, integrity, updates**
- **AVB 2.0: `libavb`, `avbtool`, `vbmeta`, chained partitions, rollback indexes** (CODE, MIT/BSD/Apache mixed per file [S48]). Sign your boot and OS images with your own key and target YELLOW state on OEMs that implement a user-settable root of trust (Pixel `avb_custom_key`; others device-by-device) [S24][S25][S26].
- **Hardware key attestation with published signing keys** (PATTERN). Publish your verified-boot key fingerprints the way GrapheneOS does (`attestation.json`) and ship an Auditor-style self-verification app; lobby app developers for whitelisting rather than spoofing Play Integrity [S4].
- **Virtual A/B semantics without the full stack** (PATTERN; `update_engine`, `snapuserd`, `liblp`, `lpmake` are Apache-2.0 CODE if you want them). On a Linux userspace the same guarantees come from dm-verity-protected read-only images (EROFS or squashfs), A/B slots for `boot`/`init_boot`/`dtbo` managed by the OEM bootloader's slot metadata, and a userspace snapshot for the big image: adopt the *protocol* (slot `SUCCESSFUL` before bumping rollback index [S26], snapshot-then-merge, XOR deltas) and implement it in Rust/Go [S27][S28].
- **APEX-style modules** (PATTERN; `apexd` Apache-2.0 CODE but AOSP-coupled). Verified, versioned, loop-mounted, individually rollback-able low-level modules map cleanly onto snaps (squashfs + signatures + revisions + revert) or systemd-sysext; applying that to the Android container image, telephony stack and GPU userspace captures most of APEX's value [S29].

**Security model**
- **Per-app UID + per-app SELinux domain + seccomp + private data dirs** (PATTERN; `system/sepolicy` as Apache-2.0 reference text). On a glibc distro the practical mapping is one dynamic user per app, a cgroup, a seccomp profile and a portal-mediated filesystem (scoped storage == document/photo pickers) [S23].
- **Platform/vendor policy split with mapping files, compiled to CIL** (PATTERN). Even if you choose AppArmor or Landlock for your own services, keep the vendor's SELinux policy loadable for the Android container and version your own policy interface the way `public/` vs `private/` does [S21][S22].
- **Permission UX from Android 15-17**: one-time/session-scoped grants, local-network permission, photo-picker-first access, Private Space [S8][S10][S12].

**Graphics and power**
- **HWC-style composition offload** (PATTERN). Whatever Wayland compositor you choose, make it able to hand entire layers to overlay planes via the vendor HWC3 (through Halium's hwcomposer client) or via DRM/KMS where available, with explicit sync fences and VSYNC-driven latching; SurfaceFlinger's `validateDisplay -> getChangedCompositionTypes -> acceptDisplayChanges -> presentDisplay` loop is the reference [S31][S32].
- **Wakeup-source-based autosleep + central suspend policy** (PATTERN; kernel side is upstream Linux). Implement a `SystemSuspend` equivalent that owns `/sys/power/wakeup_count`, exposes wakelock handles over your IPC, and feeds a Battery-Historian-style timeline [S34].
- **Doze/App Standby/JobScheduler** (PATTERN). Freeze background apps with the cgroup v2 freezer, batch wakeups into maintenance windows, give apps a single job-scheduling API, and run *one* push connection (UnifiedPush or a built-in relay) that can wake frozen apps; UBports is already pursuing kernel freezing of user processes for the same reason [S35][S39].
- **AVF/pKVM + crosvm** (CODE: crosvm BSD-3-Clause; pKVM in kernel GPLv2 **[extent of upstreaming unverified]**). A protected VM is a better home than LXC for the Android app-compat layer or for a credential/keystore service on hardware that exposes KVM to the OS [S36][S37].

**Process**
- **Automated device support from factory images** (PATTERN; GrapheneOS `adevtool` is CODE, license **[unverified]**). Generate blob lists, properties and partition layouts from the OEM's stock image instead of hand-written device trees [S40].
- **CTS-like conformance for your own HAL-consumer layer** (PATTERN): VTS tests such as `vts_treble_vintf_vendor_test` show how to assert that a vendor image fulfils its manifest [S17].

---

## 6. Pitfalls to avoid

1. **Depending on Google-published device trees or kernel history.** They are gone for Pixel and arrive weeks late via a form [S1][S3]. Build tooling that works from factory images and from the OEM's GPL kernel tarball, and prefer OEMs that publish on their own (Fairphone) or partner openly (Motorola/GrapheneOS) [S44].
2. **Promising "all Android apps will work."** Any compatibility layer will fail `MEETS_DEVICE_INTEGRITY` and therefore the banking/wallet/government long tail [S5]. Say so up front; invest in hardware-attestation advocacy instead of spoofing, which GrapheneOS refuses to do and which Google actively detects [S4].
3. **Copying Doze without a push service.** Without a single sanctioned wake path, messaging apps die or apps demand exemptions [S35].
4. **Shipping a 4 KB-only userspace.** New arm64 vendor kernels may run 16 KB pages; audit every ELF for 16 KB segment alignment early [S11].
5. **Treating VNDK/Treble as a guarantee.** Expect vendors to pin to old vendor API levels and, post-Android-15, to carry their own library copies; probe the actual `vendor` image before planning which HALs are AIDL [S18][S19].
6. **Running vendor HALs with SELinux disabled.** Halium ports commonly do this; it silently removes the vendor's own hardening and may break HALs that expect labelled `servicemanager` and `vndservice_contexts` [S14][S21].
7. **Bumping rollback indexes before the slot is marked successful.** AVB's own docs warn this can brick the fallback slot [S26].
8. **Reimplementing all of Virtual A/B, APEX and update_engine.** They are optimised for OEM factories and Play delivery; take the semantics, build on dm-verity + EROFS/squashfs + your existing snap/sysext knowledge [S28][S29].
9. **Ignoring the licensing seam.** Kernel and binder driver are GPLv2; AOSP userspace (libbinder, aidl, libavb, update_engine, sepolicy, ART, SurfaceFlinger) is Apache-2.0/MIT/BSD; libhybris Apache-2.0; crosvm BSD-3. Vendor blobs are proprietary and must stay redistributable only via on-device extraction or OEM permission [S48].
10. **Assuming relockable bootloaders.** Only some OEMs implement a user-settable root of trust; Fairphone unlock requires an OEM code, and FP5 custom-key relock support is unverified here [S25][S47]. Treat ORANGE-state operation as the default and design your threat model accordingly.
11. **Underestimating cadence.** AOSP drops twice a year, Pixel kernel source lags by weeks, and Google Play and OEM policies shift yearly [S3][S6][S7]; a one-developer project must automate rebases or it will fall permanently behind.

---

## 7. Sources

- [S1] 9to5Google, "Android Open Source Project: Pixel change" (12 Jun 2025): https://9to5google.com/2025/06/12/android-open-source-project-pixel-change/
- [S2] Android Authority, "Google is not killing AOSP": https://androidauthority.com/google-not-killing-aosp-3566882
- [S3] Open Source For You, "Google makes Pixel kernel source harder to access" (Aug 2026): https://www.opensourceforu.com/2026/08/google-makes-pixel-kernel-source-harder-to-access/ ; Android Authority: https://androidauthority.com/google-pixel-kernel-code-forms-3696441/
- [S4] GrapheneOS, "Attestation compatibility guide": https://grapheneos.org/articles/attestation-compatibility-guide
- [S5] Android Developers, "Improved verdicts in Android 13 and later devices": https://developer.android.com/google/play/integrity/improvements
- [S6] Android Authority, "AOSP source code schedule" (Jan 2026): https://androidauthority.com/aosp-source-code-schedule-3630018/ ; heise: https://heise.de/-11132493
- [S7] Android Developers Blog, "Elevating Android security" (Aug 2025): https://android-developers.googleblog.com/2025/08/elevating-android-security.html
- [S8] Android Developers, "Android 16 summary": https://developer.android.com/about/versions/16/summary ; "Android 16 is here": https://android-developers.googleblog.com/2025/06/android-16-is-here.html
- [S9] AOSP site updates / android17-release: https://source.android.com/docs/whatsnew/site-updates
- [S10] Wikipedia, "Android 17": https://en.wikipedia.org/wiki/Android_17 ; nokiamob, "Android 17 features for developers": https://nokiamob.net/2026/08/17/android-17-features-whats-new-for-developers-in-2026/
- [S11] Android Developers, "Support 16 KB page sizes": https://developer.android.com/16kb-page-size
- [S12] Android Developers, "Android 15 summary": https://developer.android.com/about/versions/15/summary
- [S13] AOSP, "Generic Kernel Image": https://source.android.com/docs/core/architecture/kernel/generic-kernel-image
- [S14] AOSP, "Binder IPC": https://source.android.com/docs/core/architecture/hidl/binder-ipc
- [S15] Phoronix, "Linux 6.19-rc5 char/misc fixes Rust Binder": https://www.phoronix.com/news/Linux-6.19-rc5-char-misc ; LWN, "Rust Binder": https://lwn.net/Articles/952029
- [S16] AOSP, "Vendor Interface Object (VINTF)": https://source.android.com/docs/core/architecture/vintf
- [S17] AOSP, "AIDL for HALs": https://source.android.com/docs/core/architecture/aidl/aidl-hals ; "Audio HAL (AIDL)": https://source.android.com/docs/core/audio/aidl-implement
- [S18] AOSP, "VNDK" (deprecation in Android 15): https://source.android.com/docs/core/architecture/vndk
- [S19] UBports Forum, Halium/VNDK/GKI discussion: https://forums.ubports.com/post/89132
- [S20] Google Security Blog, "Rust in Android: move fast and fix things" (13 Nov 2025): https://blog.google/security/rust-in-android-move-fast-fix-things/
- [S21] AOSP, "Build SELinux policy": https://source.android.com/docs/security/features/selinux/build
- [S22] AOSP, "SELinux concepts": https://source.android.com/docs/security/features/selinux/concepts
- [S23] AOSP, "Application sandbox": https://source.android.com/docs/security/app-sandbox
- [S24] AVB README: https://android.googlesource.com/platform/external/avb/+/refs/heads/main/README.md
- [S25] AOSP, "Verified boot flow": https://source.android.com/docs/security/features/verifiedboot/boot-flow
- [S26] U-Boot docs, "Android Verified Boot 2.0" (rollback index storage): https://docs.u-boot.org/en/latest/android/avb2.html
- [S27] AOSP, "Dynamic partitions": https://source.android.com/docs/core/ota/dynamic_partitions
- [S28] AOSP, "Virtual A/B overview": https://source.android.com/docs/core/ota/virtual_ab
- [S29] AOSP, "APEX file format": https://source.android.com/docs/core/ota/apex
- [S30] AOSP, "Modular system components": https://source.android.com/docs/core/ota/modular-system ; "Remote Key Provisioning": https://source.android.com/docs/core/ota/modular-system/remote-key-provisioning
- [S31] AOSP, "Implement HWC": https://source.android.com/docs/core/graphics/implement-hwc
- [S32] AOSP, "SurfaceFlinger and WindowManager": https://source.android.com/docs/core/graphics/surfaceflinger-windowmanager
- [S33] AOSP, "Android Runtime (ART)": https://source.android.com/docs/core/runtime
- [S34] AOSP, "Power management": https://source.android.com/docs/core/power/mgmt
- [S35] Android Developers, "Optimize for Doze and App Standby": https://developer.android.com/training/monitoring-device-state/doze-standby
- [S36] AOSP, "Android Virtualization Framework": https://source.android.com/docs/core/virtualization
- [S37] Slashdot/ZDNet, "Google introduces Debian Linux Terminal app for Android": https://linux.slashdot.org/story/25/03/08/0158226/google-introduces-debian-linux-terminal-app-for-android
- [S38] Halium GitHub organisation (activity through 25 Sep 2026): https://github.com/Halium ; Halium scope: https://docs.halium.org/en/latest/project/Scope.html
- [S39] Phoronix, "Ubuntu Touch making progress toward Ubuntu 26.04" (fetch returned 403; search snippet only): https://phoronix.com/news/Ubuntu-Touch-Toward-26.04
- [S40] GrapheneOS release 2025111800 notes (mirror): https://piefed.nullspace.lol/c/graphene_os/p/52452/grapheneos-version-2025111800-released ; official releases page: https://grapheneos.org/releases
- [S41] CyberInsider, "Privacy-focused GrapheneOS warns..." (12 Jun 2025): https://cyberinsider.com/privacy-focused-grapheneos-warns-go
- [S42] GrapheneOS forum, "Pixel 10 support for GrapheneOS is now available" (thread title indexed Jan 2026; page did not render): https://discuss.grapheneos.org/d/25099-pixel-10-support-for-grapheneos-is-now-available ; "AOSP and Pixel device support": https://discuss.grapheneos.org/d/23080-aosp-and-pixel-device-support
- [S43] F-Droid forum / Pinggy, "F-Droid 2.0 and developer verification" (Sep 2026): https://pinggy.io/blog/f_droid_2_0_android_developer_verification/ ; https://forum.f-droid.org/t/google-will-require-developer-verification-to-install-android-apps-including-sideloading/33123
- [S44] The Register, "Motorola partners with GrapheneOS" (2 Mar 2026): https://www.theregister.com/2026/03/02/motorola_grapheneos/
- [S45] GIGAZINE, "Motorola announces partnership with GrapheneOS" (3 Mar 2026): https://gigazine.net/gsc_news/en/20260303-motorola-partnership-grapheneos
- [S46] Android Authority, "GrapheneOS Motorola phone software support plans, foldables": https://androidauthority.com/grapheneos-motorola-phone-software-support-plans-foldables-3701921 ; Linuxiac: https://linuxiac.com/motorola-announces-partnership-with-open-source-grapheneos/
- [S47] CalyxOS, Fairphone 5 install guide (OEM unlock code requirement): https://calyxos.org/install/devices/FP5/linux/
- [S48] AVB LICENSE (MIT/Apache-2.0/BSD mixed): https://android.googlesource.com/platform/external/avb/+/refs/heads/main/LICENSE
