# Blueprint (final): "Tern", a Linux phone OS built components-first

Revision date: 2026-10-03. Supersedes `blueprint-v1.md`. Three critics (hardware realism, feasibility and scope, technology maturity) raised 7 blockers (5 distinct) and 28 majors (18 distinct); Appendix C lists each and what was done.

Reading notes:

- **[verified]** means a critic or I checked a primary source on 2026-10-03; **[unverified]** means nobody confirmed it and a named spike owns it.
- The six largest changes from v1:
  1. The Fairphone 5 is a time-boxed **bring-up rig**; the product target is the Fairphone (Gen. 6).
  2. The base moves from Debian trixie to **Debian forky**, where FuriLabs and Droidian actually develop.
  3. On the Halium lane, Flatpak is described as **packaging, not a sandbox**, until a spike proves otherwise.
  4. The Qualcomm **bootloader slot is pinned and never flipped**; A/B covers the root and Halium images only.
  5. The schedule is re-baselined at 2-3 times v1, with **dated gates and a dated pivot**.
  6. Owned artefacts are cut from about 18 to **four, plus one conditional**.

## 0. Name suggestions and a one-sentence pitch

None of these names has been trademark-checked (decision D1).

- **Tern** (working name): migrates further than any other bird; short; works as a CLI name.
- **Skerry**: a small rocky island; small, independent, hard to sink.
- Causeway and Holm remain as alternatives from v1.

v1's subtitle, "for phones you can buy today", is withdrawn. Fairphone ended FP5 sales on 12 January 2026 [verified], and Tern does not boot the FP6. The subtitle returns when it does.

**Pitch:** Tern is an image-updated Debian phone OS for the Fairphone (Gen. 6) that tells you, before you switch and on the device itself, which of your apps and which parts of the hardware actually work.

**Honest sub-pitch for developers:** until gate G2, Tern is not an OS. It is four standalone tools (an update layer, a hardware test suite, an Android bridge, an app-compatibility index) and one bring-up rig. On the Halium lane it is openly a FuriOS/Droidian derivative with an immutable root. If the OS gates are missed, the tools ship on other people's systems (section 6.1).

## 1. Principles

1. **Borrow drivers, own the OS.** Vendor partitions are never rewritten. A small overlay of AOSP-built replacements (gralloc, `vndservicemanager`, init `.rc` edits) is bind-mounted over them, as every Halium port does. Each port is pinned to one tested vendor build.
2. **Adopt before inventing; abstract only after two.** No hardware contract, shell, SDK, compositor, device generator or simulator until two working instances exist.
3. **One device deep.** The product device is the FP6. The FP5 is where the lead learns porting against a known-good reference.
4. **Root updates are reversible; kernel updates are gated.** v1 claimed every update was atomic. That is not true on this hardware (section 5.3) and the document no longer says so.
5. **Tell the truth, in the product.** This now includes "sandbox: off on this device" and "emergency calling: unverified".
6. **Every component must be useful without the OS.** This is the contributor on-ramp and the pivot path.
7. **The lane is measured, not assumed.** Each device runs whichever lane passes more of `tern hwtest`.
8. **Every phase must be completable by one person.** Contributor-dependent items are listed as opportunistic and gate nothing.

## 2. Layer-by-layer architecture

"Halium lane" = vendor kernel plus Android HAL container. "Mainline lane" = close-to-mainline kernel, no Android below the apps. The two lanes are **two image variants built from one `mkosi` tree**, not one image plus a device layer: they differ in compositor build, GTK, audio server and modem stack.

| Layer | Chosen technology | Why | Borrowed from | Rejected, or known gap |
|---|---|---|---|---|
| Bootloader | OEM ABL and fastboot, ORANGE state. **ABL slot pinned to `a`, never flipped** | A Qualcomm slot is the whole firmware set (xbl, abl, tz, modem, dtbo, `vendor_boot`), and `_b` logical partitions are empty on Virtual A/B. UBports' FP5 config forces slot `a` [verified] | UBports installer configs | `qbootctl` slot flips (research only, S3); Fairphone relock; the "AVB" label (not used) |
| Boot set | `boot` + `vendor_boot` + `dtbo` on FP5; plus `init_boot` and `vbmeta` on FP6. One versioned unit with its module set | v1's "the boot image" is three to five partitions [verified] | UBports, LineageOS | Kernel and modules on separate schedules |
| Kernel, Halium lane | FP5: Qualcomm QGKI 5.4, `gki_defconfig` + `fp5_ALLYES_GKI` + `fp5_QGKI` + `halium.config` + a Tern fragment; UBports' branch is upstream. FP6: 6.1 GKI and vendor modules rebuilt from Fairphone's source | Stock GKI lacks `PID_NS`, `FHANDLE`, `USER_NS` [verified]; rebuilt modules ship in Tern's `vendor_boot` and root | Halium, UBports | Stock GKI binary; own kernel patches |
| Kernel, mainline lane | Mobian's `sdm845` kernel package (OnePlus 6), a fork with out-of-tree patches; Nura's SM7635 tree for the FP6 lane test | v1 wrongly said "Debian 6.12, zero enablement" | Mobian, Nura | Own forks |
| Initramfs | Fork of Droidian `initramfs-tools-halium`: LVM, one root-slot state machine, verity. **Mutable root until G1** | Never debug a first bring-up and an immutable layout together | Droidian | dracut rewrite; `unl0kr` by default (S7) |
| Storage | LVM in `userdata`: `root_a/b`, `halium_a/b`, `state`, `data`. EROFS with lz4 only on 5.4, squashfs as fallback. `super` untouched | 5.4 EROFS lacks zstd, big pclusters, fragments | Droidian | Resizing `super`; writing vendor into `super` |
| Driver layer | Pinned stock vendor build in LXC, plus `halium-overlay` bind mounts | Only proven route to 2023-2026 hardware | Halium, UBports | "No Tern file touches vendor" (false in v1) |
| HAL bridges | libhybris, libgbinder: FuriLabs `forky` set first; UBports' versions for Qualcomm-specific pieces if S2 fails | FuriLabs tests on MediaTek only; UBports' set runs on this exact vendor | mer-hybris, FuriLabs, UBports | Own bionic loader |
| Android system image | FP5: UBports' Halium 11 build, consumed as an artefact. FP6: Halium 14, shared with UBports | No AOSP build farm in year one | Halium, UBports | Building three generations "for coverage" |
| Base OS | **Debian forky, pinned snapshot.** Halium variant takes FuriLabs' package set whole, including their systemd 259 hold | Both upstreams build on forky; trixie plus backports is a combination nobody ships. Forky's own systemd 262 needs kernel 5.10 [verified] | FuriOS, Droidian | trixie plus ~30 backports (v1); Ubuntu; Alpine |
| Image build | `mkosi`: common base + lane variant + device packages baked in. Optional layers later as sysext **plus confext** | sysext covers only `/usr` and `/opt`; `gbinder.conf` and udev overrides live in `/etc` | GNOME OS, Duranium | Device layer as a swappable sysext before a second device exists |
| Updates | RAUC bundles, plain HTTPS download, A/B on the root and Halium LVs, try counter in one place | One state machine. Streaming needs `BLK_DEV_NBD`, so it is deferred | RAUC | Two slot dimensions (v1); "Virtual A/B semantics" label |
| Compositor | Halium: FuriLabs phoc 0.44 fork on wlroots 0.17.4 with the hwcomposer backend. Mainline: Debian phoc on DRM | Ships in a product with a shell attached. Gaps: one client-target layer, no mode switching (no 90 Hz selection), no overlay planes [verified] | FuriLabs, Phosh | See 2.1 for the corrected Qt evaluation |
| Shell, keyboard | Halium: FuriLabs' **phosh 0.57 fork with their gtk3/gtk4 forks, as a set**. Mainline: Debian forky's Phosh 0.57. Keyboard: whatever each set pairs **[unverified which]** | v1's "unforked Phosh 0.46 close to FuriLabs' pairing" was wrong by eleven releases | Phosh, FuriLabs | Phosh plugins (C/GObject on GTK3; none in year one); own shell |
| Telephony | oFono + binder plugin + `ofono-binder-plugin-ext-qti` (UBports) + `ofono2mm`; GNOME Calls, Chatty. Mainline: ModemManager | One app-facing API. `ofono2mm` interface coverage is an S2 deliverable | UBports, Droidian | Own telephony interface |
| Audio | Halium: PulseAudio + `pulseaudio-modules-droid` (documents Android 11 as its base); PipeWire and WirePlumber for video only. Mainline: PipeWire + callaudiod | The camera portal hands out a PipeWire remote, so both daemons run | mer-hybris | `audio-manager` on the critical path (five commits, one author) |
| Camera | Camera app uses gst-droid directly (FuriLabs `furios-camera`). `droidcam2v4l2` over `v4l2loopback` is a viewfinder-class stream for sandboxed apps only | The loopback gives no full-resolution stills or hardware encode | Sailfish, FuriLabs | V4L2 loopback as the whole camera story |
| Sensors, haptics, location | sensorfw hybris plugin plus the iio-sensor-proxy shim (package to be identified in S2); feedbackd; geoclue with a hybris provider **[unverified]** | Phosh consumers unchanged | Sailfish, Phosh | New sensor contract |
| Power | `batman` for governor policy only. Suspend: adopt FuriOS's or UBports' mechanism; write a minimal `tern-suspendd` only if neither transplants (3.9) | `batman` does not suspend [verified] | UBports repowerd, Android autosleep pattern | Full `tern-powerd`, freezer, attribution log |
| Apps | Flatpak (sandbox on mainline, packaging on Halium); a browser that updates on its own channel; Waydroid where an image exists; Android Bridge | Section 4 | Flathub, Waydroid | snap; click-app layer; Web App Host; own store or SDK |
| Permissions | Flatpak's permission store and portals, unchanged. The Hardware app shows sandbox state | No second authority | XDG portals | Permission Centre; indicators as Phosh plugins |
| Quality | `tern hwtest` CLI on real devices; tiers; a preflight **checklist document** | Port quality becomes a number | Nura tiers, Android VTS idea | `tern sim`, mocks, `tern preflight`, `tern device init`, `tern lint` (all deferred) |
| Tooling, installer | Go for CLI and daemons; Python or TypeScript (GJS) for libadwaita apps; Kotlin for the Bridge companion; C only for upstream patches. UBports Installer (Electron, YAML configs, GPL-3.0) with a Tern config | Fits the lead's skills except Kotlin, C and kernel work, which get learning time | UBports | Own installer; Rust system layer |

### 2.1 What is actually taken from each reference

v1's "borrowed from" labels implied lineage that was not there. Stated plainly:

| Reference | Code reused | Pattern reused | Not taken, and why |
|---|---|---|---|
| Ubuntu Touch / UBports | FP5 kernel branch, Halium 11 image, `halium-overlay`, QTI IMS plugin, Installer, possibly repowerd | Pin slot `a`; pin the vendor build; fscrypt after boot | Lomiri, Mir, click and AppArmor: one shell user, Qt5-to-Qt6 and Mir 1-to-2 migrations in flight. Re-evaluated on a date (below) |
| Halium | Container layout, generic system image per vendor API level | Port keyed by vendor API level | Nothing rejected; this is the base of the Halium lane |
| Droidian / FuriOS | initramfs, libhybris set, phoc/wlroots hwcomposer backend, phosh and GTK forks, `ofono2mm`, `batman`, `flatpak-hybris` (as the unsandboxed mode) | Debian plus Phosh on Halium | Mutable apt-managed root; `flatpak-hybris` as the default |
| postmarketOS / Nura | SM7635 kernel tree for the FP6 lane test | Device tiers with automatic demotion; upstream-first | Alpine/musl base: libhybris and the Halium middleware assume glibc |
| Android | Vendor HALs in the container; Waydroid | `adevtool`-style mining of a factory image (later); autosleep and wakelocks | AVB (bootloader stays unlocked), `update_engine`, Virtual A/B, Doze: none are used, and v1's labels are removed |
| OpenHarmony / HarmonyOS | **None** | Two candidates, both deferred: picker-first permissions (already what XDG portals do) and data-encryption classes | Distributed soft bus, ArkUI, HDF drivers, AccessToken: each needs kernel or framework pieces no phone here ships |
| Sailfish / mer-hybris | `pulseaudio-modules-droid`, sensorfw, droidmedia, gst-droid | None beyond the code | Lipstick and Silica: Qt 5, partly closed |

**Qt 6 / QML, re-evaluated on correct facts.** v1 rejected Qt Wayland Compositor because "no Qt 6 hwcomposer QPA exists". That was false: LuneOS packages `qt6-qpa-hwcomposer-plugin`, and Droidian has one requiring Qt 6.9.2 [verified]. The GPLv3 objection is also withdrawn, since Tern's own code is GPL-3.0-or-later. For Qt: QML and JavaScript sit closer to the lead's TypeScript than C/GObject does, and Ubuntu Touch 24.04-2.0 ships a Qt 6 Morph browser (Chromium 134) with hardware acceleration on hybris [verified], the only GPU-accelerated browser known on that lane. Against: there is no Qt 6 phone shell to adopt. Lomiri's Qt 6 migration is ongoing, LuneOS's shell is webOS, and writing a shell alone is the classic project-killer. phoc and Phosh are chosen because they ship in a product with a shell attached, not on toolkit merit. **Re-evaluation gate:** when Ubuntu Touch 26.04 ships Lomiri on Qt 6 and Mir 2, or on 1 October 2027, whichever is first, compare "Lomiri as Tern's Halium-lane shell" against the FuriLabs set.

### 2.2 Dependency ledger, version 0

S2 completes it with patch counts and licences.

| Component set | Source | Tested on Qualcomm API 30? | Bus factor and licence notes |
|---|---|---|---|
| wlroots 0.17.4 hwcomposer, phoc 0.44, phosh 0.57, gtk3, gtk4, systemd 259 | FuriLabs `forky` | No (MediaTek phones) | One organisation; upstream wlroots is at 0.20. phoc fork: no licence file detected |
| libhybris, libgbinder, droidmedia, gst-droid, sensorfw, bluebinder | FuriLabs / mer-hybris / UBports | UBports' versions: yes, on FP5 | bluebinder has AIDL support |
| `pulseaudio-modules-droid` | mer-hybris | Android 11 is its documented base | No AIDL audio path |
| oFono binder plugin, `ext-qti` | UBports, Droidian | Yes, but VoLTE breaks SMS in testing | GPL-2.0 |
| `ofono2mm` | Droidian | Unknown | Last pushed January 2026 |
| `batman`, `droidcam2v4l2`, `flatpak-hybris`, `audio-manager` | FuriLabs | No | Almost all commits by one author; two have no detected licence |
| Waydroid | upstream; FuriLabs `andromeda` fork | n/a | No `HALIUM_14` vendor image |

Nothing without a licence file is mirrored or redistributed until its authors confirm one.

### 2.3 End-of-life calendar

| Component | Date | Effect |
|---|---|---|
| Linux 5.4 upstream | Ended 3 Dec 2025 | FP5 kernel fixes come only from Fairphone and Qualcomm |
| Android 11 (Halium 11, Waydroid `HALIUM_11` = LineageOS 18.1) | No patches since early 2024 | FP5 rig only; stated on its device page |
| wlroots 0.17 | Unmaintained upstream | Halium compositor depends on FuriLabs |
| Linux 6.1 upstream / `android14-6.1` | Dec 2027 / 1 Jul 2029 [verified] | FP6 kernel horizon on the Halium lane |
| Debian forky | Testing until released (two-year cadence suggests mid-2027, **[unverified]**) | No outside tester before it is stable |
| FP5 rig | Retired when FP6 passes Bronze, when FuriLabs stops holding systemd below 260, or on 30 June 2028 | No FP5 "users" exist to strand |
| Fairphone's FP6 support | Through 2033 | Product horizon |

## 3. Hardware adaptation strategy

### 3.1 Device eligibility rule

1. Quota-free documented bootloader unlock, and published kernel source including vendor modules.
2. The preflight checklist (3.4) shows no red line.
3. Kernel 5.10 or newer. The FP5 rig is the single exception and carries no users.
4. v1's rule that someone other than the lead must own each later device is **deleted**. The FP6 is the lead's device.

### 3.2 Device plan

| Device | Role | Lane and base | Status today |
|---|---|---|---|
| Fairphone 5 (QCM6490) | **Bring-up rig**, second-hand. No outside users, no Gold tier | Halium 11, vendor API 30, QGKI 5.4, pinned to the Fairphone OS Android 13 build UBports requires | UT port at 97.4%; VoLTE experimental; dual SIM and LED not working [verified] |
| Fairphone (Gen. 6) (SM7635) | **Product device** | Decided by spike S8: Halium 14 on 6.1, or mainline | Halium: UBports repository at "the beginning of the journey", no ETA [verified]. Mainline: all three cameras, audio and an end-to-end 112 call via `imsd` reported in August 2026 [verified]; fingerprint and suspend **[unverified]** |
| OnePlus 6 (SDM845) | Mainline variant: built in CI, booted in QEMU, smoke-tested on the phone monthly. Bridge development host | Mainline, Mobian's kernel package | Never a Halium target (its UT port is Halium 9 on 4.9) |
| Pixel 8/9, OnePlus 13, Pixel 10 | Watch list only | n/a | Source gated or unlock restricted; no spike before Phase 3 |
| FuriLabs FLX1s | Considered as a fallback Halium reference and **rejected** | n/a | The whole `forky` set works there, but it is MediaTek and already ships FuriOS |

The FP5 stays because a first-time porter needs a complete reference port to tell their own mistakes from port gaps, and only the FP5 has one. It is not the product because it is discontinued, on an end-of-life kernel and Android 11 images, below Tern's own kernel floor, and in a regime (QGKI, HIDL composer, VNDK 30) no current phone shares.

### 3.3 The general mechanism

**Port unit.** *(vendor API level, kernel regime, pinned vendor build)*. The third element is new. UBports' FP5 port requires the Android 13 Fairphone OS build and builds its boot image at patch level 2023-12 [verified]. A user on current Fairphone OS must downgrade; relocking after a downgrade can brick. So:

- `device.toml` records the exact vendor build fingerprints tested.
- The installer reads `ro.vendor.build.fingerprint` and refuses unknown builds.
- The device page says vendor, modem and TrustZone firmware are **frozen** at that build.
- Adopting a newer vendor build is a re-validation cycle, budgeted as one. v1's Phase 3 "firmware fetcher" is demoted to a research note.

**Kernel regimes, corrected.**

1. **QGKI with vendor modules** (FP5): boot header v3, first-stage modules in `vendor_boot`, more in `/vendor`. Config changes alter symbol CRCs, so all vendor modules are rebuilt and shipped in Tern's `vendor_boot` and root image. Wi-Fi (`qca_cld3`) is a module and the first thing to break silently.
2. **GKI with OEM source** (FP6): the same, with `init_boot` and `vbmeta` in the boot set.
3. **GKI without usable source** (Pixels): unknown; not pursued.
4. **Mainline.**

**Spike S1** produces the option delta against UBports' `halium.config` (`EROFS`, `DM_VERITY`, `SQUASHFS`, `BLK_DEV_LOOP`, `USER_NS`, `PID_NS`, `NET_NS`, `CGROUP_BPF`, `v4l2loopback`, a console-capable DRM or fbdev device, optionally `BLK_DEV_NBD`), a module-load diff against stock, a mount test of the exact `mkosi`-built EROFS image on 5.4, and the cgroup hierarchy mode. Android 11's init mounts v1 controllers, so that question decides whether the container starts at all.

**Snaps.** v1 excluded them because AppArmor is absent from GKI defconfigs. That was wrong: the kernel is rebuilt anyway, and UBports enables AppArmor on this FP5 kernel. The real reasons: strict snap confinement depends on Ubuntu's AppArmor patches, AppArmor would sit beside the vendor's SELinux policy, and Tern does not want a second app format.

**Subsystem paths** are as in v1's table, with three corrections. The Halium audio lane also runs PipeWire for video. The camera app bypasses the portal. An **AIDL-only audio HAL is a red line** in preflight, because `pulseaudio-modules-droid` loads a legacy `audio.primary` library and has no AIDL path; FP6 still ships HIDL audio 7.1 [verified]. Composer3, AIDL radio and AIDL camera get the same check.

### 3.4 Preflight is a checklist, not a tool

A two-page document until a third device needs automating: boot Google's GSI; record `ro.vendor.api_level`, kernel version, boot header version and the boot-set partition list; dump `/proc/config.gz`, the VINTF manifest and `lpdump`; record firmware versions in both slots, the unlock procedure, the kernel source location, and **whether a Waydroid vendor image exists for this Halium generation**. Green means "worth starting", nothing more.

### 3.5 A port is a hand-written repository

`device-<codename>/` holds `device.toml` (lane, API level, pinned vendor builds, kernel source and fragment, boot-set partitions, cgroup mode, kernel command line), the adaptation package (with its `/etc` content), and `hwtest` waivers. The first two are written by hand from UBports' ports. A generator is written only when a third port starts.

### 3.6 Kernel-floor policy

Unchanged in substance: new ports need 5.10 or newer and there are no systemd backports. The FP5 exception now has an end date (2.3) instead of a product life. Kernel maintenance: on FP5 Tern carries one config fragment and no code, and UBports merges vendor updates; on FP6 the base is Fairphone's tree plus the same fragment.

### 3.7 Conformance tiers

| Tier | Requires |
|---|---|
| Bronze | Boots to Phosh; display; touch; Wi-Fi; root OTA and automatic rollback, including boots with no SIM and in airplane mode |
| Silver | Calls with correct routing (earpiece, speaker, wired, Bluetooth HFP); SMS; mobile data; proximity blanking in calls; suspend entered, with wake on call, SMS and RTC alarm; time-in-suspend ratio and idle drain published. **Emergency calling:** either the dialling path is tested by the carrier's permitted procedure, or first boot shows a permanent "not your only phone" banner |
| Gold-minus-VoLTE | Camera stills and video; GNSS with time-to-first-fix published; fingerprint where present; MMS; three consecutive OTAs on the rig |
| Gold | The above, plus VoLTE passing a call series on the lead's carrier, with SMS working while VoLTE is on |

v1's "50 calls on two carriers" is dropped until someone funds a second carrier. Call tests run between the rig phone and the OnePlus 6 on two prepaid SIMs. Automatic demotion stays.

**Emergency calling is a safety item, not a waiver.** Phosh and GNOME Calls support emergency calls through ModemManager's API, disabled by default, and not without a SIM [verified, 2023 post, possibly stale]. Whether that works through `ofono2mm` is **[unverified]**. On a VoLTE-only network, a phone without working IMS cannot call 112 or 911. No outside tester receives an image until this is tested or the banner is in place.

### 3.8 Two lanes, and the FP6 lane decision (spike S8)

v1's in-place migration from Halium to mainline is removed from the pitch and roadmap: the lanes are different image variants and nobody has done such a migration. What replaces it is a measured choice for the product device:

| | FP6 on Halium 14 | FP6 on mainline |
|---|---|---|
| App sandbox and GPU | hybris; sandbox weak (5.2) | Mesa; Flatpak sandbox intact; browsers accelerated |
| Android gate | No `HALIUM_14` Waydroid image exists | Waydroid `MAINLINE` image (LineageOS 20), rebuilt 27 Sep 2026 |
| Compositor and shell | wlroots 0.17.4 fork set; AIDL composer3 unproven on that backend | Upstream phoc and Phosh |
| Hardware | Vendor camera, fingerprint, IMS in principle | Camera quality poor; fingerprint and suspend drain unknown; VoLTE experimental |
| Others doing the work | UBports, early | Fairphone's own engineer and Nura, active |

**Rule:** the lane that first passes Bronze plus calls with audio plus suspend on the lead's FP6 becomes the product lane. If both pass, mainline wins, because it removes the fork ledger and restores the sandbox. Recent phones still generally need vendor drivers; the FP6 may be the exception because its vendor posted mainline patches at launch, so Tern measures instead of assuming.

### 3.9 Suspend (new; v1 had no owner for it)

Nothing in v1's stack suspended the phone: `batman` only tunes governors, cores and radios, and Ubuntu Touch's 24 h figure comes from repowerd and libsuspend. A plain logind suspend ignores Android wakelocks and races the RIL, which means missed calls. Spike S6, in order:

1. Ask FuriLabs how FuriOS suspends, and reuse it.
2. Try UBports' repowerd headless under Phosh.
3. Only then write `tern-suspendd`, the conditional fifth artefact, in Go: a `wakeup_count` or autosleep loop, a bridge to `/sys/power/wake_lock`, display-state signalling to oFono, RTC wake alarms, clearing `lpm_levels.sleep_disabled` and triggering vendor post-boot scripts at boot-complete, and WoWLAN setup.

`hwtest` gains suspend-entry count, time-in-suspend ratio, and wake latency for call, SMS and alarm. **Waydroid policy:** as on Ubuntu Touch, no suspend while the container runs; idle drain is published separately for "Android gate running".

### 3.10 Inherited status and known gaps

"Inherit" means Tern expects the reference port's behaviour and does not plan to fix it.

| Area | Position |
|---|---|
| Dual SIM | Inherit: not working on UT's FP5 port |
| MMS, USSD, cell broadcast | Depend on `ofono2mm` coverage (S2) |
| Wi-Fi calling, RCS | Not offered |
| Bluetooth | HFP call audio through the droid audio HAL is a Silver test; A2DP codecs as the vendor stack offers |
| GNSS | A-GPS, XTRA and SUPL without the Android framework **[unverified]**; time-to-first-fix is measured, not promised |
| Hardware video codecs | gst-droid codecs are not reachable from browsers; expect software decode and its battery cost |
| Display | No refresh-rate selection; cutout data, brightness and double-tap-to-wake live in the adaptation package; no external display |
| Charging, thermal | Vendor thermal engine runs in the container; offline-charging mode and UPower battery reporting are S2 checks |
| USB | Follow UT: usb-moded and umtprd for MTP and tethering; SSH over USB networking for `hwtest` |
| Debug and recovery | The Halium initramfs's USB telnet; pstore/ramoops; UART availability **[unverified]**. Tern's `vendor_boot` replaces the stock recovery, so factory reset is a Tern initramfs mode. **Return to stock is a tested, documented procedure before G2** |
| Fingerprint UI | FuriLabs' enrolment UI lives in their forked gnome-control-center, taken with the set on the Halium lane |
| Accessibility, localisation | Inherited from Phosh and GTK; Tern's own apps use gettext; no screen-reader claim |
| Memory and wakeups | Budgets are set after the first measurement on the rig and recorded per release; a regression above 10% fails the release |

## 4. App model and ecosystem strategy

### 4.1 Position

Tern builds no SDK and no store. v1's promise to make three catalogues "feel like one platform" is cut to what one person can deliver: the Bridge, an index, and plain statements of what fails on which lane.

### 4.2 The gates, per lane

| Gate | Mainline lane | Halium lane |
|---|---|---|
| Native (Flatpak 1.18 and portals 1.22, the versions forky ships) | Stock sandbox, Mesa GL | **Default: stock Flatpak, software rendering, sandbox intact. Opt-in per app: "accelerated, unsandboxed" through `flatpak-hybris`** |
| Web | The chosen browser, GPU-accelerated | Browser chosen by spike S5; possibly CPU-rendered |
| Android | Waydroid `MAINLINE` image plus the Bridge | FP5: `HALIUM_11` image, Android 11, no security patches. FP6: none today |
| Ubuntu Touch click apps | **Removed** | **Removed** |

**Why the Halium Flatpak row changed.** Two critics read `flatpak-hybris`. It replaces `/usr/bin/flatpak` and `/usr/bin/bwrap`. Every app gets `--device=all`, read-only `/vendor`, `/system` and `/data`, and the system D-Bus socket; the wrapper strips `--unshare-net`, `--unshare-pid` and `--unshare-user` [verified]. Under it, an app can reach binder, the GPU nodes and the modem daemon. v1's claims that "no app sees binder nodes" and that a per-app network switch "needs no kernel feature" were false.

**Spike S4** (three to four weeks, right after G1) has written pass criteria:

1. An unmodified `org.gnome.Platform` app renders through hybris GLES.
2. It does so with user, PID and network namespaces unshared on the rebuilt kernel.
3. The exact device nodes, sockets and Android paths bound into the sandbox are listed, testing an allow-list (`kgsl-3d0`, dma-heap, a dedicated binderfs exposing only the allocator) in place of `--device=all`, and server-side buffer allocation so clients need no hwbinder.

If (2) fails, the software-rendered default stays and the Hardware app says "sandbox: packaging only" for accelerated apps. Host GTK is FuriLabs' patched fork while runtimes ship stock GTK, and a GL extension must be rebuilt per freedesktop runtime branch; that recurring job is costed only if S4 passes.

**Web engine (spike S5, run beside G1 because it needs only pixels).** Four candidates, measured on the FP5 for GPU compositing, scroll frame time, memory per web app, idle wakeups and Web Push:

- **Firefox**, which FuriOS configures for mobile and Droidian ships. New in this revision.
- Debian's **Chromium**. UBports developers state it cannot use libhybris, so expect software raster.
- **GNOME Web** on WebKitGTK, whose accelerated path expects DMA-BUF **[unverified on hybris]**.
- **Morph on Qt 6**, the only engine known to be accelerated on hybris (under Lomiri; under phoc **[unverified]**), but patched by UBports and outside Debian's security support.

The browser must update independently of the OS image, as a Flatpak or on its own weekly channel. The Web App Host is deleted; Tern uses the chosen browser's own web-app install feature. If no engine is GPU-accelerated on hybris, the web gate is described as slow on the Halium lane, and that weighs on the S8 lane decision.

**Ubuntu Touch click apps** are removed. `furios-lomiri-app-support` ships prebuilt shared objects with no licence file, pulls in Qt 5 WebEngine, and runs apps unconfined [verified]. The lead's own UT apps are better ported to GTK4 or packaged as Flatpaks.

### 4.3 The Android Bridge (standalone project)

A Go host daemon plus a small Kotlin companion app. Delivery order is unchanged: launcher entries with a "runs in Android" badge; notification forwarding through the companion's listener; URL, intent and clipboard handling; later, container policies.

It is developed and released against **stock Waydroid on Mobian on the OnePlus 6**, where it is useful today, and reaches a Tern Halium device only where an image exists. Spike S9 answers three questions: does a LineageOS 20 system image run over the `HALIUM_11` vendor layer; does `andromeda` publish newer Halium images; and is camera sharing done through the host camera provider, as UT's FP5 port does, or through a V4L2 loopback HAL? App Compass records results per container Android version. Defaults are unchanged: F-Droid only, microG opt-in, no Aurora, no APK redistribution.

### 4.4 App Compass

Version 0 only: a static site generated from YAML in Git, answering per app "native, web, Android gate (with container version), or fails integrity checks". The Android companion app that scans a user's current phone is deferred.

### 4.5 Play Integrity

Unchanged: `MEETS_DEVICE_INTEGRITY` is impossible inside Waydroid; wallets, many banking apps and Widevine L1 fail; Tern never spoofs verdicts.

### 4.6 Push and background

Deferred with the freezer. When it returns, Tern adopts KUnifiedPush instead of writing a distributor. How many GTK apps implement the UnifiedPush D-Bus API is **[unverified]**, so push is not in the pitch.

## 5. Security, privacy and update model

### 5.1 Threat model

Tern does not claim GrapheneOS-class security. On the Halium lane the kernel is the vendor's, the bootloader is unlocked, vendor HALs run as root under a permissive SELinux policy, **vendor, modem and TrustZone firmware are frozen at the pinned build**, and the Android-derived images are frozen (Android 11 on the rig). v1 claimed "integrity, containment and recoverability". The claim is now **recoverability and corruption detection everywhere, containment on the mainline lane only**.

### 5.2 Mechanisms, per lane

| Area | Mainline lane | Halium lane |
|---|---|---|
| Image integrity | EROFS under dm-verity; an ed25519-signed manifest checked in the initramfs | Same. This is **corruption detection, not verified boot**: an attacker with fastboot replaces the initramfs that checks it |
| Data at rest | LUKS2 with `unl0kr` | **fscrypt after boot, as UT's FP5 port does**, until spike S7 shows `unl0kr` can draw and take touch in the initramfs on the vendor kernel. PIN strength depends on KeyMint-wrapped keys **[unverified]** |
| App containment | Flatpak with bubblewrap, seccomp and portals | **Default** software-rendered apps: same. **Accelerated** apps: none, until S4 passes |
| Per-app network switch | Flatpak `--unshare=network` (needs `NET_NS`) | Sandboxed apps: same. Accelerated apps: only outside bwrap. nftables `socket cgroupv2` needs kernel 5.13 [verified], so not on the FP5; systemd's cgroup-BPF `IPAddressDeny=` on the app scope is **[unverified]** under Android's cgroup layout |
| Vendor container | n/a | Vendor partitions read-only; separate binderfs for Waydroid is S9, not an assertion |
| Indicators | Via PipeWire and portals, where Phosh 0.57 supports them | **None**: droidmedia and PulseAudio bypass the mediation indicators rely on. The Hardware app says so |
| Defaults and supply chain | No telemetry or account; MAC randomisation; DNS over TLS; hardened systemd units; SBOM from the `mkosi` manifests | Same |

Removed from v1: Landlock assumptions; "OpenHarmony-style encryption levels" (fscrypt layered on LUKS would double-encrypt, and evicting keys under running GTK apps is unsolved); SELinux enforcing in the container.

### 5.3 Update model

**One state machine.** A Tern slot is the pair {root LV, Halium LV}. The initramfs keeps one try counter in the `state` LV and falls back after three failed boots. The bootloader slot never changes, so no second A/B dimension exists. 

**Kernel updates are the non-atomic step.** The boot set and its modules must match. So:

- Every root image carries modules for exactly the kernel build IDs it lists, and the initramfs refuses a root slot whose list lacks the running kernel.
- A kernel change ships in two releases: first a root image with modules for both old and new kernels on both slots, then the new boot set.
- A boot-set release must pass `hwtest` on the rig, including Wi-Fi module load, before it is published.
- If a new boot set fails to boot, recovery is `fastboot flash` of the previous set from a laptop. That procedure is documented and tested, and the limitation is stated on the device page.

**Spike S3 is read-only first:** `lpdump` of `super`, firmware versions in both slots, whether slot `b` is populated from the factory, and the vendor's own boot-control HAL as an alternative to `qbootctl`, whose README warns it "may or may not render any hardware you run it on unusable". True dual boot sets (clone every slotted partition from `a` to `b`, resolve vendor from a fixed slot) stay research until they survive 50 flips on the lead's device. There is no public EDL loader for a bricked FP5.

**Boot-complete** means: the HAL container reached its ready property; the compositor presented a frame; oFono exposes a modem object in any SIM state; the updater can write the `state` LV. Never network registration, Wi-Fi association or user unlock.

**Before any outside tester:** a power-cut and interrupted-write test matrix, and rollback tests with no SIM and in airplane mode.

**Channels:** `edge` for the lead, and `tested`, monthly with security roll-ups. Three channels and six-month stable releases wait until three people can cut a release.

**Installer:** the UBports Installer with a Tern YAML config. It verifies the pinned vendor fingerprint and flashes the boot set to slot `a`. LVs are created on first boot by the initramfs. Virtual A/B snapshot metadata is not touched, because Tern never triggers a vendor OTA.

## 6. Differentiators, honestly

| Versus | Where Tern would be better | Where Tern is worse |
|---|---|---|
| **Ubuntu Touch** | Root A/B with automatic rollback; Flatpak and web apps as peers; a published conformance score; honesty about gaps in the product | Everything else today: 111 devices, a funded team, a 97.4% FP5 port, convergence, a GPU-accelerated browser on hybris, working suspend. v1's "not waiting on a toolkit migration" is withdrawn: Phosh is itself mid-port from GTK3 to GTK4 |
| **Nura** | A glibc base where Halium middleware lives; an Android bridge; image rollback | Nura's upstream-first work is durable and Tern mostly consumes it, entirely so if S8 picks mainline |
| **Droidian / FuriOS** | Immutable root and rollback; conformance tiers; the Hardware app; a secure-by-default Flatpak mode | It *is* this stack, minus FuriLabs' engineers and hardware. If FuriOS adopts image updates, most of the gap closes |
| **GrapheneOS** | A real Linux userland; not tied to Google hardware | Security, app compatibility, camera, polish. If security or banking apps come first, GrapheneOS or /e/OS is the rational choice and Tern's site should say so |

### 6.1 The alternative: do not build an OS

Evaluated on merit, it is the stronger plan on every measure except the one the lead cares about.

| | Components on existing systems | A new OS |
|---|---|---|
| Time to first real user | Months: `hwtest` and the Bridge can target Mobian, Droidian and UT as they are | Three years or more |
| Maintenance | Four repositories | Those four, plus a fork ledger, a kernel, images, updates and support |
| What it cannot deliver | An immutable, rollback-safe image with honest device pages as one product | n/a |

So the plan is built so that **the first nine months are identical under both**: Phase 0 and most of Phase 1 are useful if the OS never ships. The OS is attempted because it is the lead's goal and because Mobian, Droidian and FuriOS are all apt-managed, with no image rollback. It is abandoned on a date if the gates are missed (section 7).

## 7. Roadmap

**Baseline.** Every duration is given as full-time / evenings, and evenings is the default assumption until decision D2 says otherwise. Bring-up rows carry a threefold allowance over v1. Phase lengths include a standing 15% "rebase tax" for tracking FuriLabs' set, a 30% operations allowance from the first outside tester, and learning time: the lead is assumed new to Halium porting, kernel configuration, initramfs work and audio-HAL routing.

| Work item | Full-time weeks, low-high | Skill match |
|---|---|---|
| Experiment E1 and UT baseline dumps | 1-2 | New |
| S1: kernel build, option delta, module diff | 2-3 | New |
| `mkosi` image, CI, QEMU boot | 2-3 | Good |
| RAUC plus initramfs state machine in QEMU | 4-8 | Partial (shell) |
| `hwtest` v0 CLI | 3-4 | Good (Go) |
| S2: middleware matrix and ledger | 3-4 | New |
| Tern-built image to pixels and touch on FP5 (G1) | 6-12 | New |
| Modem, SMS, data | 2-4 | New |
| S4, S5, S6, S7 | 3-4, 1-2, 3-6, 1 | Mixed |
| Bridge v0 and App Compass v0 | 5-7 | Go good; Kotlin new |
| Immutable layout on device, power-cut matrix (G2) | 6-8 | Partial |
| Call audio, Bluetooth, sensors, suspend integration | 6-10 | New |
| S8 (FP6 lanes), S9 (Waydroid on Halium) | 4-6, 1-2 | New |

Total to G2, excluding S8 and S9: 48-78 full-time weeks before the allowances.

### Before week 1

- Resolve **D8**: does the lead's carrier still have 2G/3G voice fallback, for both the FP5 and the OnePlus 6?
- Write to FuriLabs, to UBports' FP5 and FP6 porters, and to Droidian. State what Tern intends to consume. Ask: is any maintained device API 30; how does FuriOS suspend; is GNOME Shell on hybris replacing Phosh; what would they accept upstream; under what licence are the unlicensed repositories? Record the answers as decision records.
- Draft an **NLnet Restack** application for the standalone test suite and Bridge. Grants are EUR 5,000-50,000; the next deadline is 3 November 2026 [verified]. The NGI Zero Commons Fund held its final call in June 2026, so v1's "after M1" risks missing the money.
- Buy a second-hand FP5 and a second OnePlus 6.

### Phase 0: first 90 days full-time, six months evenings. Gate G0

| Weeks (full-time) | Work | Output |
|---|---|---|
| 1-2 | **Experiment E1** (below) and baseline dumps from the FP5 running Ubuntu Touch | Go/no-go on the borrowed stack |
| 3-4 | Spike S1; S3 read-only part | Option delta, module diff, slot facts |
| 5-7 | `mkosi` forky image with Phosh booting in QEMU; nightly CI on free arm64 runners | Image artefact |
| 8-10 | RAUC with the single state machine in QEMU; broken-image rollback; interrupted-write tests | Rollback demonstrated in QEMU only |
| 11-12 | `hwtest` v0 CLI, run against the OnePlus 6 on Mobian and the FP5 on Ubuntu Touch; published standalone | First public repository |
| 13 | Buffer; ledger v1; write-up | G0 review |

**Experiment E1 (weeks 1-2).** Install Ubuntu Touch on the FP5 with the UBports Installer. Record `lpdump`, `/proc/config.gz`, `getprop`, `lshal` and both slots' firmware versions. Then keep UBports' kernel, `vendor_boot` and Halium 11 image, replace only the root filesystem with a Debian forky root carrying FuriLabs' packages (starting from Droidian's generic api30 rootfs if a current one is published, **[unverified]**), and run `test_hwcomposer`, `test_egl`, then phoc and Phosh. **Pass:** Phosh on screen with touch. **Fail:** repeat with UBports' libhybris versions under FuriLabs' compositor. Either result settles S2's hardest question for the price of a used phone.

**G0 exit:** image boots in QEMU with rollback; E1 and S1 answered in writing; upstream replies recorded; grant application submitted.

### Phase 1: to month 9 full-time, month 18 evenings. Gate G1

- **G1:** a Tern-built, *mutable* forky image shows Phosh with touch on the FP5; oFono sees the modem; an SMS is sent.
- S2 complete: `test_hwcomposer`, `test_audio`, `test_camera`, `test_sensors` and modem enumeration pass with FuriLabs' host packages against UBports' Halium 11 image, or the named fallback (UBports' host middleware, with only phoc and wlroots from FuriLabs) is adopted. Deliverables: the completed ledger, the licence audit, the `ofono2mm` coverage table.
- S4, S5, S6 and S7.
- **S8a, a desk exercise:** build the FP6 6.1 kernel and vendor modules from Fairphone's source with the fragment, to prove the source is complete. One critic wanted the whole FP6 spike in Phase 0; it is split instead, because a first-time porter should not run two bring-ups at once.
- Bridge v0 (launcher entries and notifications) released for stock Waydroid on Mobian. App Compass v0.

**Pivot criterion, replacing v1's empty "move to another device":** if G1 is not met by **31 July 2027 (full-time) or 30 April 2028 (evenings)**, the OS stops. `hwtest`, the Bridge, App Compass and the RAUC layer continue as contributions to Mobian, Droidian and UBports. No fallback device exists under Tern's own eligibility rule.

### Phase 2: to month 18 full-time, month 36 evenings. Gate G2

- **G2:** immutable layout and RAUC rollback on the FP5; return-to-stock tested; power-cut matrix passed.
- FP5 rig at Silver, including suspend with wake on call and the emergency-call item. The lead carries it for seven days. The exit has two written variants, with and without circuit-switched fallback on the lead's carrier; if VoLTE is required, four to six weeks move here from the Bridge.
- **Spike S8b, first item of the phase,** on a newly bought FP6: boot the Halium 14 container on the S8a kernel and run `test_hwcomposer`; in parallel run `hwtest` against Nura on the same phone, then boot Tern's mainline variant on Nura's kernel. Findings go to UBports' FP6 repository instead of waiting behind it. **Lane decision recorded.**
- FP6 at Bronze on the chosen lane.

**Decision point at the end of Phase 2:** if neither FP6 lane shows display plus modem, Tern is the FP5 rig image plus components. It then says so publicly and stops calling itself a phone OS for current hardware.

### Phase 3: to month 36 full-time; evenings beyond

- FP6 to Silver, then Gold-minus-VoLTE: camera, GNSS, fingerprint.
- `tested` monthly channel; operations set up (section 8).
- First outside testers.
- Opportunistic, needing people who do not yet exist: forward-porting the hwcomposer backend toward current wlroots (a survival item, since every Phosh release widens the gap); a PipeWire droid module; a second device; UnifiedPush.

**Exit criterion, solo-passable:** FP6 at Silver; **three outside testers for 14 days** (v1 required ten for 30 days plus two contributors); three consecutive root OTAs and one boot-set OTA with no unrecoverable device.

## 8. Team and community plan

**Contributors are opportunistic.** v1's Phase 2 could not exit without a contributor with Halium audio and telephony skills, which perhaps a dozen people have, most employed by FuriLabs, Jolla or UBports. No exit criterion now depends on anyone but the lead. v1's "nothing announced before M1" is replaced: **components are published the day they work on Mobian; the OS is not announced before G2.**

On-ramps, in order of realism: `hwtest` (Go, any Phosh distribution); the Android Bridge (Go and Kotlin, any Waydroid user); App Compass entries (no programming); fixes sent to UBports' FP6 port.

Upstream-first is a goal for fixes under about 50 lines; larger ones are carried as patches with an issue filed.

**Operations**, absent from v1:

- OTA hosting on an object store without egress fees.
- Signing key on a hardware token, with an offline copy held by a named second person.
- Crash intake by an opt-in `tern report` tarball attached to an issue; nothing automatic.
- One chat room and one tracker for support.
- A `security.txt`, and a seven-day target for Debian-fixed CVEs to reach `tested`.

**Year-one budget.** Prices are estimates, **[unverified]**.

| Item | EUR |
|---|---|
| Fairphone 5, second-hand | 250-350 |
| Second OnePlus 6, second-hand | 80-120 |
| Fairphone (Gen. 6), bought for S8b; from about 500 refurbished | 500-600 |
| USB relay and serial board | 30 |
| Two prepaid SIMs on two carriers, 12 months | 150-250 |
| Domain, object storage | 100-200 |
| CI | 0 (GitHub's arm64 Linux runners are free for public repositories [verified]) |
| Build machine | 0 if the lead's workstation suffices; no AOSP build in year one |
| **Total** | **about 1,100-1,550** |

Unpaid full-time work is itself a funding assumption, which is why evenings is the baseline.

**Licensing** is unchanged (GPL-3.0-or-later on device, Apache-2.0 for tools, CC BY-SA for data, DCO), with these additions. A licence audit of every ledger entry precedes mirroring. Rebuilt kernels and vendor modules carry GPLv2 source-publication duties, met by publishing the tree and fragment per release. OnePlus 6 firmware is checked against "nothing redistributed" before any public mainline image.

**AI policy and governance** are unchanged from v1. Regulatory notes: the modem firmware is unmodified vendor firmware; emergency calling is handled in 3.7; Cyber Resilience Act duties attach to a commercial partner, not to this project.

## 9. Risk register

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| 1 | One unpaid developer; scope still too large | High / fatal | Four artefacts; evenings baseline; dated pivot; components survive |
| 2 | FuriLabs moves to GNOME Shell and mutter on hybris, or its single key engineer leaves | Medium / high | Ask before week 1; ledger; UBports middleware fallback; Qt 6/Lomiri gate; FP6 mainline lane |
| 3 | FuriLabs' MediaTek-tested set fails on Qualcomm API 30 | Medium / high | E1 in week 1; S2 with a named fallback |
| 4 | hwcomposer backend stays on wlroots 0.17 while Phosh moves on | High / high | Consume FuriLabs' fork set whole; forward-port is opportunistic; the mainline lane escapes it |
| 5 | Kernel update bricks or strands a device | Medium / high | Slot pinned; boot-set gating on the rig; tested fastboot recovery; no dual-slot until proven |
| 6 | No working emergency call on a VoLTE-only network | High per market / severe | Silver-tier item; banner; no outside tester without it |
| 7 | VoLTE on Qualcomm stays broken (frozen calls, SMS lost) | High / high | Gold-minus-VoLTE tier; carrier check first; work item with UBports only if required |
| 8 | Halium-lane apps are unsandboxed or slow | High / medium | Secure software-rendered default; S4; truthful Hardware app; mainline lane for FP6 |
| 9 | No Android gate on FP6 Halium; no GPU-accelerated browser on hybris | Certain today, medium / medium | Stated per device; S9; S5 with four candidates; both weigh on S8 |
| 10 | Suspend unreliable; missed calls; drain | High / high | S6; suspend metrics in `hwtest` |
| 11 | Vendor firmware frozen; security incident | Medium / high | Stated in the threat model; re-validation cycles |
| 12 | Unlicensed borrowed repositories; forky churn before release | Medium / medium | Audit and ask before mirroring; pinned snapshots; no outside tester before forky is stable |
| 13 | Mobian's sdm845 kernel fork lapses; grant windows close | Low-medium / medium | Lane is CI-only and mirrored; apply for 3 Nov 2026 |
| 14 | Play Integrity spreads; "yet another OS" indifference | High / medium | App Compass; standalone components |

## 10. Open decisions for you

| # | Decision | Recommendation |
|---|---|---|
| D1 | Name | Trademark and domain search on Tern and Skerry before the first public repository |
| D2 | Time commitment | Assume evenings. If full-time, say for how long and what funds it |
| D3 | Hardware now | A used FP5 and a second OnePlus 6. The FP6 waits for S8b |
| D4 | Positioning | "Components first; on Halium, a FuriOS derivative". Accept this or do not start |
| D5, D9, D10, D13 | Android defaults; licence split; AI policy; legal home | As in v1 |
| D6 | Browser | After S5. Prior: Firefox |
| D7 | Forge | GitHub (free arm64 runners), mirrored to GitLab |
| D8 | Carrier | Check 2G/3G fallback **before buying anything** |
| D11 | Pixels | Watch list only |
| D12 | Ubuntu ties | The UBports Installer and Incus builders; no snaps or click apps on device |
| D14 | **FP6 lane** | Decide by measurement at S8; mainline wins ties |
| D15 | **Qt 6 / Lomiri** | Re-evaluate on the gate date in 2.1; do not start a shell |
| D16 | **Grant** | Apply to NLnet Restack for 3 November 2026 |
| D17 | **Pivot** | Commit now, in writing, to the G1 dates |

## 11. Sources

New or re-checked on 2026-10-03:

- Debian systemd versions (257.13 stable, 262 testing): https://api.ftp-master.debian.org/madison?package=systemd&s=trixie,forky,sid
- FuriLabs systemd fork (new-mount-API reverts, January 2026): https://github.com/FuriLabs/systemd/commits/forky
- Kernel longterm dates: https://www.kernel.org/category/releases.html ; GKI branch lifetimes: https://source.android.com/docs/core/architecture/kernel/android-common
- NLnet open calls: https://nlnet.nl/funding.html ; Commons Fund closed: https://nlnet.nl/commonsfund/
- Droidian 101 (sid base, wlroots 0.17.4, Firefox 142, api30/api32 variants): https://forum.droidian.org/t/droidian-101-discussion-thread/40
- UBports FP6 port: https://forums.ubports.com/post/94806 , https://gitlab.com/ubports/porting/reference-device-ports/halium-14/fairphone-6
- FP6 mainline status, August 2026: https://linmob.net/weekly-update-34-2026/
- Ubuntu Touch Qt 6 Morph and 26.04 plans: https://ubports.com/blog/ubports-news-1/ubuntu-touch-q-a-192-4002
- UBports Installer: https://github.com/ubports/ubports-installer
- Emergency calls in Phosh and Calls: https://phosh.mobi/posts/emergency-calls/
- nftables cgroup v2 matching (Linux 5.13): https://blog.fraggod.net/2021/08/31/easy-control-over-applications-network-access-using-nftables-and-systemd-cgroup-v2-tree.html
- GitHub arm64 runners: https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/
- FuriLabs Firefox configuration (archived April 2026, successor `mobile-config-firefox-furios`): https://github.com/FuriLabs/furios-firefox-tweaks

Verified by the critics and relied on here:

- UBports FP5 installer config and port repository: https://raw.githubusercontent.com/ubports/installer-configs/master/v2/devices/FP5.yml , https://gitlab.com/ubports/porting/reference-device-ports/android11/fairphone-5/fairphone-fp5 , https://devices.ubuntu-touch.io/device/FP5/release/noble
- Boot-set partitions: https://raw.githubusercontent.com/LineageOS/lineage_wiki/main/_data/devices/FP5.yml , https://raw.githubusercontent.com/LineageOS/lineage_wiki/main/_data/devices/FP6.yml
- `qbootctl`: https://github.com/linux-msm/qbootctl
- `flatpak-hybris`: https://raw.githubusercontent.com/FuriLabs/flatpak-hybris/forky/src/flatpak-hybris.sh , https://raw.githubusercontent.com/FuriLabs/flatpak-hybris/forky/src/bwrapwrapper.sh
- FuriLabs versions: https://raw.githubusercontent.com/FuriLabs/phoc/forky/meson.build , https://raw.githubusercontent.com/FuriLabs/phosh/forky/meson.build , https://raw.githubusercontent.com/FuriLabs/wlroots/forky/meson.build , https://raw.githubusercontent.com/FuriLabs/wlroots/forky/backend/hwcomposer/hwcomposer2.c
- Qt 6 hwcomposer QPA: https://layers.openembedded.org/layerindex/recipe/32393 , https://github.com/droidian/qt6-qpa-hwcomposer-plugin
- Waydroid images: https://ota.waydro.id/vendor/waydroid_arm64/HALIUM_11.json , https://ota.waydro.id/vendor/waydroid_arm64/HALIUM_13.json ; `andromeda`: https://github.com/FuriLabs/andromeda
- `batman`: https://github.com/FuriLabs/batman ; `pulseaudio-modules-droid`: https://github.com/mer-hybris/pulseaudio-modules-droid ; `furios-lomiri-app-support`: https://github.com/FuriLabs/furios-lomiri-app-support
- Qualcomm VoLTE field state: https://forums.ubports.com/post/82716
- FP5 end of sales: https://support.fairphone.com/hc/en-us/articles/24114770139154-Fairphone-5-End-of-Sales
- Chromium and libhybris: https://forums.ubports.com/post/51884
- Phosh GTK4 port: https://nlnet.nl/project/Phosh-GTK4/ ; plugin types: https://gitlab.gnome.org/World/Phosh/phosh/-/tree/v0.57.0/plugins
- sysext scope: https://www.freedesktop.org/software/systemd/man/latest/systemd-sysext.html
- RAUC kernel requirements: https://rauc.readthedocs.io/en/latest/integration.html

v1's source list (GKI defconfigs, Play Integrity, Pixel and OnePlus policies, Nura, Flutter) still applies and is not repeated.

## Appendix A: judge disagreements (from v1), as amended

Items 1-3, 5-9 and 15 stand. Amended:

- **Item 4, year-one devices:** FP5 is a rig; FP6 is the product; Pixels are a watch list.
- **Item 10, base:** forky, not trixie. The AppArmor reasoning is corrected (3.3).
- **Item 11, updater:** RAUC stays; the bootloader slot is pinned.
- **Item 12, FuriLabs as upstream:** accepted more fully. The set is consumed whole instead of being backported.
- **Item 13, compositor:** phoc stays, for a corrected reason, with a dated Qt 6/Lomiri gate.
- **Item 14, FP5 base:** Halium 11, plus a pinned vendor build.

## Appendix B: factual corrections

v1's corrections 1-4 and 6-15 stand. Correction 5 (`qbootctl` for slot marking) is withdrawn. New corrections, sourced in section 11: a Qt 6 hwcomposer QPA exists; FuriLabs pairs phoc 0.44 with a forked phosh 0.57 and forked GTK on forky with systemd 259; Phosh is still GTK3 and its plugins are C; `flatpak-hybris` removes namespace isolation; `batman` does not suspend; Waydroid has no `HALIUM_14` image and `HALIUM_11` is Android 11; UBports' FP5 port needs the Android 13 vendor build, pins slot `a` and flashes `vendor_boot`; Mobian's OnePlus 6 kernel is its own fork; FP5 sales and Linux 5.4 have ended; sysext does not cover `/etc`; Flatpak 1.18 and portals 1.22 are forky's versions, not trixie's.

## Appendix C: changes from v1

Issue IDs: H = hardware-realism critic, F = feasibility-scope critic, T = technology-maturity critic. Every blocker and major led to a change; none is rebutted outright. Where I declined part of a proposed fix, the disagreement list below says why.

**Blockers**

| Issue | What was done |
|---|---|
| H1, T8, F11: A/B design treats a Qualcomm slot as a kernel slot; two state machines | Slot pinned to `a`; one state machine over {root, Halium} LVs; boot set of 3-5 partitions; kernel updates gated, not atomic; S3 moved to weeks 3-4, read-only; return-to-stock tested before G2 (2, 5.3) |
| H2, T1, F5: Flatpak containment false on Halium | Per-lane table; packaging-only statement; secure software-rendered default; S4 is a 3-4 week security spike with pass criteria; "needs no kernel feature" deleted (4.2, 5.2) |
| F1, T2: FP5 is a dead-end product device | FP5 is a rig with an end date; FP6 is the product; GKI-regime spike split into S8a (Phase 1, desk) and S8b (first item of Phase 2); EOL calendar; title withdrawn (0, 2.3, 3.2, 7) |
| F2: Phase 0 compresses 26-46 weeks into 13 | Evenings baseline; threefold bring-up allowance; gates G0, G1, G2 with dates; mutable root first; `tern sim`, generator, preflight tool and OnePlus 6 RAUC work deleted; effort table (7) |
| F3: phases gated on contributors who do not exist | Principle 8; solo-passable exits; three testers for 14 days; ownership rule deleted; contact letters before week 1; components published early (1, 7, 8) |

**Majors**

| Issue | What was done |
|---|---|
| H3: suspend has no owner | Section 3.9; S6; suspend metrics; Waydroid policy |
| H4, F4, T3: trixie plus unforked Phosh is a combination nobody ships | Forky base; FuriLabs set consumed whole; ledger; 15% rebase tax; gtk3/gtk4 added; lanes are two variants |
| H5, T6, F16: Waydroid images do not match the plan | Per-device gate table; S9; Bridge developed on Mobian; preflight line |
| H6, F9: port tied to one vendor build | Pinned build in `device.toml`; installer check; fetcher demoted; principle 1 reworded |
| H7, T15: QGKI modules; EROFS, NBD and `unl0kr` on 5.4 | Regime 1 rewritten; S1 deliverables; lz4-only EROFS; streaming deferred; S7 |
| H8, T4: Qt rejection rested on a false fact | 2.1 re-argues on real grounds, with backend gaps and a dated gate |
| H9, F15: VoLTE and emergency calls | Emergency item in Silver; Gold split; D8 first; two exit variants |
| H10: registration as a health signal | Boot-complete redefined; no-SIM and airplane tests |
| H11, F10: untested stack; empty fallback | E1 in week 1; S2 at 3-4 weeks with UBports middleware as the named fallback; FLX1s rejected with reasons; G1 failure means pivot |
| F6, T7: no known GPU path for either web engine | Firefox and Morph added; S5 beside G1; independent browser channel; Web App Host deleted |
| F7: two lanes are two OS variants | Variants stated; mainline demoted to CI plus monthly smoke test; confext added; migration removed from the pitch |
| F8: about 18 artefacts, several outside the lead's languages | Four plus one conditional; UBports Installer reused; C, Kotlin and kernel work named and budgeted |
| F12: no budget; grant timing | Budget table; Restack application for 3 Nov 2026 |
| F13: operations unbudgeted | Two channels; 30% allowance; key custody; support and security process |
| T5: Phosh is GTK3; plugins are C; indicators | No plugins in year one; standalone libadwaita apps; indicators stated as absent on Halium; differentiator withdrawn |
| T9, F14: `furios-lomiri-app-support` | Removed |
| T10: bus factor, licences, MediaTek-only testing | Ledger; licence audit; UBports as source for Qualcomm pieces; `audio-manager` and `batman` off the critical path |
| T11: "borrowed from" labels imply false lineage | Table 2.1; AVB, Virtual A/B and Doze labels removed; OpenHarmony stated as "none" |

**Minors.** H12 (camera path and PipeWire), H14 (Mobian kernel), H15 (AIDL audio red line), H16 (cgroup question moved to S1), T12 (confext), T13 (versions and PipeWire) and T14 (AppArmor reasoning) are all fixed in place. H13 (`unl0kr`) becomes spike S7 with fscrypt as the default.

**Where the critics disagreed, and what I chose**

1. **Slot design.** F wanted root slots derived from the ABL slot using ABL retry counters. H and T showed the ABL slot switches firmware and the UFS boot LUN, and F marked its own ABL claims as from memory. I chose H's option (a), a pinned slot. F's principle, one source of truth, is kept.
2. **FP5.** F: learning rig only, go to FP6. T: keep it as a bring-up vehicle with a sunset. H: the FP5 direction is sound. I chose rig with an end date, and FP6 as product.
3. **Power daemon.** F: defer `tern-powerd`, use `batman`. H: `batman` cannot suspend. H is right on the facts; F is right on scope. Hence adopt first, then a minimal daemon as a conditional artefact.
4. **Base.** F and T offered forky or trixie-with-tax; H suggested UBports' middleware. I chose forky with FuriLabs' set, and H's suggestion as the S2 fallback.
5. **Flatpak default.** H proposed software rendering as the secure default; T proposed a network switch outside bwrap; F proposed deleting the rows if S4 fails. All three are adopted, in that order.

**Items the critics listed as missing**, and where they now are: emergency calling and call-test method (3.7); suspend (3.9); Bluetooth call audio, GNSS, video codecs, dual SIM, MMS, cell broadcast, display, charging, USB, debug and recovery, fingerprint UI, accessibility, resource budget (3.10); installer (5.3); kernel maintenance (3.6); upstream contact, effort table, learning allowance, solo path and pivot (7); budget, operations, key custody, licence audit, regulatory notes (8); ledger and EOL calendar (2.2, 2.3); "do not build an OS" (6.1); Halium image source and frozen security state (2, 5.1); vendor baseline policy (3.3); confext and keyboard (2); architecture-only items from v1 (deferred in the Quality and Permissions rows); GTK rendering and the GL extension (4.2); `ofono2mm` coverage (S2); OpenHarmony and Qt 6 statements (2.1); UnifiedPush clients (4.6).

**Not resolved, stated as such:** whether FP5 ships with both firmware slots populated; whether FuriLabs' set runs on Qualcomm API 30; how FuriOS suspends; whether any browser is GPU-accelerated on hybris under phoc; whether emergency calls work through `ofono2mm`; Debian forky's release date; the prices in the budget.
