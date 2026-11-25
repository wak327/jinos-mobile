# Why mobile OS projects died or survived, and the 2026 market/regulatory reality

Research date: 2026-10-02. Everything below about "current status" was checked against 2025-2026 sources (URLs in section 7). Items I could not verify are marked **unverified**.

## 1. Architecture: how each project reached hardware, and the control points that decide survival

The dead and the living projects split cleanly along one axis: **how they got drivers**.

| Project | Base / UI stack | Hardware path | Outcome |
|---|---|---|---|
| Firefox OS (2013-2015) | Gonk (Android kernel + HAL) + Gecko + HTML5 "Gaia" UI | Android vendor blobs via Gonk | Killed Dec 2015; lives on as KaiOS |
| webOS (Palm/HP, 2009-2011) | Linux + WebKit-based Luna UI, JS apps | Palm's own BSPs (TI OMAP, Qualcomm) | HP dropped hardware in 2011 after ~7 weeks of TouchPad; open-sourced; LG uses it on TVs |
| MeeGo / Maemo (Nokia/Intel, 2010-2011) | Linux + Qt, RPM | Nokia in-house BSP (N9, TI OMAP3) | Abandoned by Nokia Feb 2011 ("burning platform"); community Mer -> Sailfish |
| Tizen mobile (Samsung, 2015-2017) | Linux + EFL, web apps | Samsung's own low-end Spreadtrum SoCs | Last phone Z4 (2017); Tizen Store closed 31 Dec 2021 |
| Canonical Ubuntu Touch (2013-2017) | Ubuntu + Mir + Qt/Unity 8; Android in an LXC container + libhybris | Android vendor blobs via libhybris | Dropped April 2017; continued as UBports |
| Sailfish OS (Jolla, 2013-) | Mer core + libhybris + Qt/Silica (closed UI) + Android AppSupport (proprietary) | Android blobs via libhybris; now ships own MediaTek phone | Alive; new Jolla Phone shipping since July 2026 |
| Librem 5 / PureOS (Purism, 2017-) | Debian + Phosh (wlroots/GTK), mainline kernel, no blobs | i.MX8M Quad with separate modem on M.2 | Alive but niche; PureOS Crimson released 2026 |
| Fuchsia | Zircon microkernel, Flutter | Google-only | Never a phone; Chrome-for-Fuchsia dropped 2025; Nest Hubs only |
| KaiOS (2017-) | Gonk-like Android base + Gecko (KaiOS 4.0: Gecko 123, Android 14 base, 5G) | Qualcomm blobs via Android HAL | Alive; 170M+ devices shipped (vendor claim), ~0.01% global share |
| GrapheneOS / LineageOS / /e/OS | AOSP forks | Android vendor blobs natively | Alive; GrapheneOS Pixel-only until Motorola devices (2027) |
| UBports Ubuntu Touch | Ubuntu 24.04 + Lomiri + Halium (Android container + libhybris) | Android blobs via Halium | Alive; 24.04-2.0 released 24 Jul 2026 |
| postmarketOS | Alpine 3.24 + systemd 261 + Phosh/Plasma Mobile/GNOME Mobile | Mainline or close-to-mainline kernels, no Android | Alive; 26.06 released 21 Jun 2026 |
| FuriOS (FuriLabs) | Debian/Droidian + Halium/libhybris + Android container | Android blobs via Halium (MediaTek Dimensity) | Alive; FLX1s+ shipping, $499 |
| Volla | Volla OS (de-Googled Android) or Ubuntu Touch preinstalled, multi-boot | Android blobs; UBports commercial partner | Alive; Quintus €719 |

Beyond drivers, five **external control points** now decide whether a non-Google OS is usable at all on a current phone: the bootloader-unlock policy (and whether you can relock with your own AVB key), Play Integrity / hardware attestation, the IMS stack for VoLTE, eSIM provisioning (SGP.22), and RCS. Section 4 covers each.

## 2. What the survivors do well (patterns)

1. **A legal home that is not a company's product line.** UBports is a German charitable foundation; GrapheneOS is a non-profit foundation; postmarketOS is community-run with NGI/NLnet grants (listed on ngi.eu for v25.12 + v26.06). None of them can be cancelled by a CEO memo. Every death in section 3 was a corporate cancellation.
2. **A hardware partner that preinstalls the OS and sells it.** Murena ships Fairphone (Gen. 6+) with /e/OS at €699 (Aug 2026); Volla sells Ubuntu Touch preinstalled and co-funds UBports; FuriLabs and Jolla build their own phones; Motorola will ship GrapheneOS devices in 2027. The OS projects that only ever "ported to someone else's phone" (Firefox OS on ZTE/Alcatel, Tizen Z1-Z4) died.
3. **An Android app story that is pragmatic, not ideological.** Sailfish AppSupport (Android 15 / API 35 in 5.2), Waydroid on Ubuntu Touch/FuriOS, or being AOSP itself (Lineage, Graphene, /e/). Firefox OS and Tizen bet on web apps replacing native and lost.
4. **Narrow, deep hardware support instead of wide, shallow.** GrapheneOS: Pixel only, every feature works, relockable verified boot. UBports: Fairphone 5 at 97.4% on 24.04 is "the best supported device". postmarketOS demotes devices from "community" to "testing" when kernels go stale (five demoted in 26.06).
5. **Predictable cadence.** postmarketOS: two releases a year (25.06, 25.12, 26.06). UBports: 24.04-1.x point releases roughly quarterly, 24.04-2.0 in July 2026. LineageOS: yearly major (23 = Android 16, Oct 2025). Cadence is what keeps contributors and device maintainers around.
6. **Upstream-first where possible.** Phosh, phoc, feedbackd, ModemManager, lpac, Lomiri (in Debian) are shared across postmarketOS, PureOS, Mobian, UBports and even Sailfish community repos. The dead projects (Gaia, Luna, EFL phone UI, Unity 8 before Lomiri) were single-project stacks.
7. **A paying niche, not "the next billion".** KaiOS survives on carriers (Reliance Jio holds 16%) and SoftPOS merchant payments; Jolla capped pre-orders at 10,000 and sold the first batch in 48 hours at €499; Purism sells a $1,999 "Liberty Phone" with US supply chain. Each has a customer who pays for the specific thing the OS does.

## 3. Why they died / lessons learned

Recurring causes of death, with the evidence:

1. **Single-sponsor dependency.** Nokia dropped MeeGo in Feb 2011 after concluding "the emperor had no clothes" and that only three MeeGo devices would ship before 2014. HP abandoned webOS hardware weeks after the TouchPad. Mozilla ended Firefox OS phones on 9 Dec 2015 because it "weren't able to offer the best user experience". Shuttleworth ended Ubuntu phone in April 2017 citing "commercial constraints": "In the community, our efforts were seen fragmentation not innovation" and the industry took "a 'better the devil you know' approach". Samsung stopped Tizen phones after the Z4 (2017). Google never shipped Fuchsia on a phone and dropped Chrome for Fuchsia.
2. **Competing on price at the bottom of the market.** Firefox OS's $25 phone "had not seen sufficient traction" (internal memo, May 2015). Tizen Z1-Z4 were low-end India phones. Any OEM that can build a cheap Linux phone can build a cheaper Android phone with a full app store. Lesson: do not sell on cost; sell on something Android cannot do.
3. **Chasing feature parity with Android/iOS.** Ben Francis's Firefox OS retrospective (2017) names this directly: trying to compete on app count and feature parity, and building what carriers and OEMs demanded instead of what users and web developers needed. Tizen's "lack of killer apps became its Achilles' heel". Analyst Jack Gold on Firefox OS: "they should never have launched in the first place."
4. **Announcing unfinished products.** Palm announced the Pre six months before launch, developers got no SDK until months later and could not charge for apps until two months after launch; HP shipped the TouchPad on a WebKit-based UI that was "noticeably slower". Ubuntu Edge (2013) never shipped. Librem 5 was crowdfunded in 2017 and reached shipping parity years late. Lesson: ship a working daily-driver on one device before any announcement.
5. **Talent drain after acquisition.** Matias Duarte left Palm for Google soon after the HP buyout; "in a way, H.P. didn't acquire WebOS: Rather, Google did."
6. **Building a UI stack in isolation.** Gaia (HTML), Luna (WebKit), Unity 8/Mir (pre-Lomiri) each had one user. When the sponsor left, the stack had no home. Lomiri survived only because UBports moved it toward Debian.
7. **Betting on a single hardware vendor you do not control.** GrapheneOS's "Pixel paradox": a de-Googled OS whose only hardware was Google's. In 2025-2026 Google stopped Pixel device trees with Android 16, moved the AOSP reference to Cuttlefish, stopped publishing QPR source, moved AOSP drops to Q2/Q4 and (August 2026) put Pixel kernel source behind a Google Form with weeks of delay and no commit history. LineageOS 23 is "based on the initial Android 16 release, not QPR1" for exactly this reason. GrapheneOS's answer was an OEM partnership (Motorola) and hosting its own code.
8. **Convergence as the headline.** Canonical sold "phone that becomes a desktop" before the phone worked. Convergence is a good feature after the phone is a phone.

## 4. Current status as of 2026-10-02

### Survivors
- **UBports / Ubuntu Touch**: 24.04-2.0 and 24.04-1.4 released 24 Jul 2026 (Chromium 134 Morph, Widevine, fscrypt v2, printing, notch avoidance); work toward 26.04 underway; initial Flatpak support pending merge; Vulkan on Halium demonstrated on FuriLabs FLX1. Fairphone 5: 97.4% on noble, Android 13 / Halium 11 base, kernel 5.4.289, VoLTE "experimental, carrier-dependent". OnePlus 6 (the user's device): **not supported on 24.04**; last release 20.04 at 93.8%. Foundation's stated goal: 50 more developers and €1M funding (older post; 2026 funding status **unverified**).
- **postmarketOS**: 26.06 "Alpen Avocado" (21 Jun 2026): Alpine 3.24, systemd 261, Phosh 0.55 (greetd + phrog), Plasma Mobile 6.6.5, GNOME 50, Plymouth, sudo-rs default, ModemManager with cell broadcast; 16+ community devices, 254 testing devices. Fairphone 6 port exists with a close-to-mainline kernel; in 2025 WiFi, modem, calls and SMS were broken (2026 state **unverified**: the wiki URL redirected to an unexpected host and I did not follow it).
- **GrapheneOS**: Pixel 10 stable since 10 Jan 2026 (unlock, flash custom verified-boot key, relock confirmed). Motorola partnership announced at MWC (March 2026); first devices 2027, Snapdragon flagships (Razr Ultra/Fold, Signature), relockable verified boot promised. Rewriting bundled apps; own RCS client with MLS E2EE planned (Sept 2026), initially still needing sandboxed Play Services for RCS activation.
- **LineageOS**: 23 (Android 16) released 13 Oct 2025 for 100+ devices incl. Pixel 9a, OnePlus 13; security patch currency constrained by Google withholding QPR source.
- **/e/OS / Murena**: Murena Fairphone (Gen. 6+) €699/$699 (Aug 2026), /e/OS V4, updates "at least through 2033"; sold via Fairphone and Murena.
- **Jolla / Sailfish**: Sailfish OS 5.2 (Android 15 AppSupport, Gecko ESR115, "bootloader unlock capability", Privacy Switch). New Jolla Phone (MediaTek Dimensity 7100, 8/128 or 12/256, 5450 mAh replaceable, €499 pre-order / €649 list, EU+UK+NO+CH only): first deliveries 8 Jul 2026, 2,500+ delivered by 27 Aug 2026, batch 3 targets 10,000. eSIM and VoLTE not in the spec sheet; eSIM is community lpac via Chum, official support roadmapped for 5.x.
- **FuriLabs**: FLX1s ($550 pre-order, Dimensity 900, 8/128, three kill switches, 5G incl. n71) and FLX1s+ ($499 now, 48 MP camera) shipping; FuriOS = Droidian/Debian + Halium; 15 FuriOS releases in three years. VoLTE/eSIM claims **unverified** from their site.
- **Volla** (Volla Systeme GmbH, Germany): Phone Quintus €719 (Dimensity 7050, 8/256), Plinius €598, Plinius+ €698, X23 €564, Tablet €698; ships Ubuntu Touch or Volla OS, multi-boot; distributors Herweck/Telepart; UT device page lists Quintus as "Advanced" support.
- **Purism**: PureOS Crimson (Debian 12 base) released April/May 2026 after 5+ years; Librem 5 still sold ($799-$999), Liberty Phone $1,999; "PureOS Dawn" next. Company finances **unverified**.
- **KaiOS**: 4.0 (May 2025) Gecko 123, Android 14 base, 5G on Qualcomm SM4635; ~0.01% global share, 16% in India; pivoting to SoftPOS merchant payments.
- **SHIFT**: SHIFTphone 8 (QCM6490, same SoC as Fairphone 5; 12/512) shipped 2025-Jan 2026 with ShiftOS-G/-L (Android 14/15); custom ROMs allowed; mainline Linux patches submitted before launch; LineageOS and iodé builds exist.

### Bootloader-unlock policy per vendor
- **Fairphone**: unlockable (unlock code from Fairphone), alternative OSes officially tolerated and sold (Murena). FP6: /e/OS, LineageOS nightlies, postmarketOS experimental, Ubuntu Touch started; CalyxOS/iodé not yet.
- **Google Pixel**: unlockable on non-carrier models, custom AVB key + relock works (Pixel 10). But: no device trees since Android 16, kernel source by request form since Aug 2026, AOSP drops Q2/Q4, QPR source withheld. Developer verification for sideloading rolls out Sept 2026 (BR/ID/SG/TH), global 2027, on certified devices only.
- **OnePlus**: China/ColorOS 16 "Deep Testing": 60-day account, real-name + face verification, 7 days logged in on the device, max 4 devices per identity per year, 14-day window. Global OxygenOS devices not yet affected (sources express concern it will spread).
- **Samsung**: One UI 8 (July 2025) removed "OEM Unlocking" worldwide (androidboot.other.locked=1); previously US-only lock. Effectively closed.
- **Xiaomi**: HyperOS: application via Community app with quiz, approval 3-7 days, one device per account per year (global), 336-hour binding window, unlocked devices excluded from HyperOS OTA. Official global post **not fetched** (page required JS); details from secondary sources.
- **Nothing**: fastboot unlock with no waiting (2025 sources); support said unlocking voids warranty (2022); relock-with-custom-key **unverified**.
- **Motorola**: historic official unlock portal; committed to relockable verified boot on select 2027 flagships for GrapheneOS.
- **Sony**: Open Devices program continues (Xperia 1 IV/5 IV/10 IV/10 V AOSP trees), site migrating to a new Sony Corporation domain from 10 May 2026 (new URL not announced); unlock voids warranty for most issues historically.

### EU regulation
- **DMA**: the 16 Jul 2026 Alphabet decision (Art. 6(7)) opens 11 Android features to rival **AI assistants** by Android 18 (1 Aug 2027); it says nothing about bootloaders, alternative OSes or certification. Do not expect the DMA to force OEMs to allow your OS.
- **Cyber Resilience Act**: vulnerability reporting from 11 Sep 2026, full compliance (CE marking, SBOM, lifetime updates) from 11 Dec 2027. Non-commercial FOSS (donations without profit intent, non-profit development) is exempt; a foundation can be a light-touch "open source steward". The moment you or a partner **sells hardware with your OS preinstalled**, that seller is a manufacturer with full obligations. Plan the SBOM and CVD process early.
- **Ecodesign (EU) 2023/1670**, in force 20 Jun 2025: OS updates for 5 years after the last unit is placed on the market, spare parts 7 years, 800-cycle batteries, repairer access to firmware. No bootloader-unlock or end-of-life-unlock obligation.
- **EU age verification app**: maintainers stated (11 Jul 2026) that "hardware-backed attestation is a requirement of this project"; if the wallet uses Play Integrity, GrapheneOS and every non-certified OS is excluded. Expect more government apps to behave like banks.

### Play Integrity and banking
Banking apps check Play Integrity (OS membership in Google's certification program), not hardware robustness. GrapheneOS has convinced roughly a dozen apps to accept the AOSP hardware key attestation API with a published list of verified-boot key fingerprints (`grapheneos.org/attestation.json`: verify the chain, accept `verifiedBootState` Verified or SelfSigned, match `verifiedBootKey`). A Linux-based OS (no AOSP keystore/attestation) cannot pass either path; banking on a Linux phone means Waydroid with a Play-less app, a web banking site, or a second device. State this honestly to users.

### VoLTE, eSIM, RCS
- **VoLTE** is mandatory after 2G/3G shutdowns (US done 2022; France 2G in 2026, 3G 2028-29; Sweden before 2025). Android implements IMS in proprietary vendor code. UBports' path: ofono **binder** plugin talking to the Android radio HAL; MediaTek (Volla) first, Qualcomm via `ofono-binder-plugin-ext-qti` requiring radio HAL 1.5, still dropping calls and freezing in testing. An earlier sysmocom proposal for an open IMS stack (Doubango-based) got Phase 1 funding only. postmarketOS mainline devices depend on modem-firmware IMS via ModemManager/QMI (per-device; **not verified** here).
- **eSIM**: `lpac` (SGP.22 v2.2.2, ESTKME Technology, Hong Kong; cross-platform) plus `lpa-gtk` "eSIM Manager" for Linux Mobile; on Sailfish via Chum. Works only when the modem exposes an APDU path (AT/QMI/MBIM); failed on Xperia 10 V in user reports.
- **RCS**: no open client exists. On Android it is split across OS, Google Messages and Play Services (Jibe). GrapheneOS is building its own client (Sept 2026) but still needs sandboxed Play for activation. For a Linux OS, treat RCS as unavailable and plan on Matrix/Signal plus SMS/MMS.

## 5. Borrowable ideas for a new OS

- **Governance**: a non-profit foundation from day one (UBports e.V./German charitable model; GrapheneOS Foundation), with a commercial partner that sells hardware (Volla/UBports model) so the project is neither a hobby nor a product line.
- **Hardware reach**: Halium (Android container + libhybris, Apache/GPL mix) is the only proven way onto current phones; FuriOS shows Debian + Halium can be a shipped product. Keep a mainline lane (postmarketOS style, pmbootstrap, close-to-mainline kernels on QCM6490/SM7xxx) for the 3-6 year tail.
- **Telephony**: ofono with the **binder plugin** (`ofono-binder-plugin`, Jolla-originated, GPLv2) for Halium devices; ModemManager (LGPL/GPL) for mainline; `lpac` + `lpa-gtk` for eSIM; ModemManager cell-broadcast (26.06) for emergency alerts.
- **Device database as a product**: devices.ubuntu-touch.io's per-release percentage and feature matrix, and postmarketOS's community/testing tiers with automatic demotion. Make "97.4% on noble" a first-class metric.
- **Attestation posture**: publish signed verified-boot key fingerprints like `attestation.json` even if only Waydroid can use them; ship custom AVB key + relock only on devices that support it (Pixel, future Motorola, Fairphone partially).
- **Shared UI plumbing**: Phosh/phoc/feedbackd/greetd/phrog and Plymouth are packaged in Alpine, Debian and Fedora; Lomiri is in Debian. Reuse, do not fork.
- **Release engineering**: six-month cadence with codenames (pmOS), release-channel RCs with public freeze dates (UBports 24.04-1.2: freeze 6 Feb, release 19 Feb 2026), and a published SBOM (CRA-ready).
- **Android apps**: Waydroid (LXC + binder, GPLv3) or a Sailfish-style AppSupport; sandboxed-Play approach from GrapheneOS as the reference for "Google services as an unprivileged app".
- **Business niche**: Jolla's capped pre-order batches (2,000 units, €99 refundable deposit) de-risk hardware; KaiOS's SoftPOS shows a vertical can fund an OS.

## 6. Pitfalls to avoid

1. Depending on one hardware vendor you do not control (Pixel paradox; Google's 2025-2026 source lockdown).
2. Launching on cheap hardware to compete on price (Firefox OS, Tizen).
3. Promising convergence, desktop mode or "the next billion" before calls, SMS, VoLTE, camera and battery life work on one phone.
4. Announcing before a daily-driver exists (Pre, TouchPad, Ubuntu Edge, Librem 5 timelines).
5. Building a bespoke UI toolkit/compositor that only your project uses; if you choose Qt/QML, use what Lomiri/Plasma Mobile already maintain; if GTK, use Phosh/phoc. Evaluate on merit, but never alone.
6. Targeting Samsung, Xiaomi, or Chinese-market OnePlus: locked or quota-gated bootloaders, OTA penalties, identity verification.
7. Ignoring Play Integrity: tell users up front that banking and EU government apps may not work; build the Waydroid story and web fallbacks.
8. Underestimating VoLTE: it is vendor-specific binder tracing work per modem family; budget for it per SoC (MediaTek vs Qualcomm), and prefer SoCs where UBports/FuriLabs already have IMS working.
9. Shipping preinstalled hardware in the EU without CRA readiness (SBOM, CVD policy, 11 Sep 2026 reporting duties).
10. Letting the port rot: OnePlus 6 fell off Ubuntu Touch 24.04 despite 93.8% on 20.04. Automate rebuilds and define a demotion policy.

### Which vendors to target or partner with
- **Fairphone (first)**: unlockable, sells alternative OSes officially, upstreams kernel patches, 7-year parts, QCM6490 (FP5) and Snapdragon 7s Gen 3/Gen 4 (Gen. 6/6+). Best-supported Ubuntu Touch device today; ports take ~2 years, so start with FP5/Gen. 6.
- **SHIFT**: SHIFTphone 8 shares QCM6490 with FP5; mainline patches upstream; custom ROMs allowed. Cheap second target reusing FP5 work.
- **Volla**: already pays for and preinstalls Ubuntu Touch; MediaTek Dimensity 7050; VoLTE on MediaTek via ofono binder is furthest along. Natural first commercial partner for a Halium-based OS.
- **FuriLabs**: Halium + Debian vertical; proven Vulkan on Halium; Dimensity. Potential code-sharing partner (Droidian lineage) more than hardware partner.
- **Jolla**: Dimensity 7100 phone with "bootloader unlock capability" and a European customer base; Sailfish UI is closed, so a partnership is unlikely, but the hardware is a candidate target after they ship 10,000 units.
- **Murena**: software and cloud company, not hardware; partner for App Lounge/cloud or distribution, not ports.
- **Motorola (2027)**: watch; relockable verified boot on Snapdragon flagships would be the first non-Pixel path to a locked custom OS.
- **Google Pixel**: technically still the best verified-boot platform, politically the worst trend line; keep as a developer target only.
- **Sony Open Devices**: usable (Xperia 10 V/1 IV AOSP trees) but tiny market and warranty-hostile.
- **Avoid**: Samsung (no unlock), Xiaomi (quota/quiz, OTA penalty), OnePlus China (identity verification); OnePlus global is usable today but trending the same way.

## 7. Sources

Post-mortems
- Firefox OS end (Computerworld, Dec 2015): https://www.computerworld.com/article/3013534/mozilla-shutters-firefox-os-gives-up-on-smartphones.html
- Ben Francis, "The Story of Firefox OS" (summary): https://liliputing.com/2017/03/firefox-os-developer-provides-not-brief-history-operating-system.html and https://medium.com/@bfrancis/the-story-of-firefox-os-cb5bf796e8fb
- webOS (MIT Technology Review): https://www.technologyreview.com/2012/01/02/188591/was-webos-doomed-from-the-start/
- MeeGo / burning platform (BGR): https://bgr.com/general/an-exec-recounts-the-moment-nokias-burning-platform-scorched-meego/
- Tizen Store closure (Gizchina): https://www.gizchina.com/samsung/samsung-permanently-closed-tizen-store-didnt-survive-in-the-android-era
- Shuttleworth, April 2017: https://ubuntu.com/blog/growing-ubuntu-for-cloud-and-iot-rather-than-phone-and-convergence
- Fuchsia status (GoogleWatchBlog, Mar 2025): https://www.googlewatchblog.de/2025/03/fuchsia-ist-tot-googles-neues-betriebssystem-wird-nicht-mehr-gebraucht-verliert-alle-geraete-und-plattformen/
- GrapheneOS "Pixel paradox": https://urandom.io/blog/2026-02-17-grapheneos-the-pixel-paradox

Survivors
- UBports blog index (24.04-2.0, 24 Jul 2026): https://ubports.com/blog/ubports-news-1
- UBports 24.04-1.2 tracking: https://gitlab.com/ubports/development/project-management/-/issues/22
- UT Fairphone 5 (noble): https://devices.ubuntu-touch.io/device/FP5/release/noble
- UT OnePlus 6: https://devices.ubuntu-touch.io/device/enchilada/release/noble
- UT toward 26.04 (Phoronix): https://phoronix.com/news/Ubuntu-Touch-Toward-26.04
- UBports funding goal: https://ubports.com/blog/1/post/ubports-foundation-wants-to-attract-50-extra-developers-and-1-million-in-funding-to-optimize-alternative-independent-mobile-operating-system-ubuntu-touch-3819
- postmarketOS 26.06 (Linuxiac): https://linuxiac.com/postmarketos-26-06-brings-fresh-linux-phone-updates/
- postmarketOS NGI funding listing: https://ngi.eu/?p=67466
- postmarketOS on FP6 (Fairphone forum): https://forum.fairphone.com/t/postmarketos-on-fairphone-6/121763
- LineageOS 23: https://alternativeto.net/news/2025/10/lineageos-23-launches-with-android-16-application-updates-improved-vm-support-and-more
- GrapheneOS FAQ (device requirements): https://grapheneos.org/faq
- GrapheneOS attestation guide: https://grapheneos.org/articles/attestation-compatibility-guide
- GrapheneOS Pixel 10 thread: https://discuss.grapheneos.org/d/25099-pixel-10-support-for-grapheneos-is-now-available
- GrapheneOS/Motorola (Android Authority): https://www.androidauthority.com/grapheneos-motorola-partnership-announced-3645710 ; TechRepublic: https://www.techrepublic.com/article/news-motorola-grapheneos-partnership-2027/ ; Oct 2025 OEM tease: https://reclaimthenet.org/grapheneos-expands-beyond-pixel-phones-with-new-android-partner
- GrapheneOS app overhaul/RCS (Privacy Guides, 6 Sep 2026): https://www.privacyguides.org/news/2026/09/06/grapheneos-overhauled-default-apps-and-secure-clipboard/
- Murena Fairphone (Gen. 6+): https://itsfoss.com/news/murena-fairphone-6-plus/
- Jolla Phone deliveries (15 Jul 2026): https://forum.sailfishos.org/t/jolla-phone-update-deliveries-started-and-other-next-steps/30730
- Sailfish community news (27 Aug 2026): https://forum.sailfishos.org/t/sailfish-community-news-august-27-2026/32526
- Jolla Phone shop page: https://commerce.jolla.com/products/jolla-phone-sep-ii-2026
- Jolla shipping (Gigazine): https://gigazine.net/gsc_news/en/20260310-jolla-phone-start-shipping-2026/
- Sailfish eSIM threads: https://forum.sailfishos.org/t/esim-and-sailfish-os/18480 ; https://forum.sailfishos.org/t/esim-provider-and-hardware-support/29520
- FuriLabs FLX1s (Liliputing): https://liliputing.com/flx1s-is-a-new-linux-phone-thats-mostly-a-downgrade-from-the-flx1/ ; site: https://furilabs.com/
- LinMob weekly 23/2026 (Vulkan on Halium, FLX1s+): https://linmob.net/weekly-update-23-2026/
- Volla: https://volla.online/en/ ; Quintus review: https://www.linuxlinks.com/volla-phone-quintus-running-ubuntu-touch-introduction ; UT page: https://devices.ubuntu-touch.io/device/algiz
- PureOS Crimson released: https://puri.sm/posts/pureos-crimson-development-report-april-2026-pureos-crimson-released/
- KaiOS: https://en.wikipedia.org/wiki/KaiOS ; https://www.kaiostech.com/ ; share: https://gs.statcounter.com/os-market-share/mobile/worldwide
- SHIFTphone 8: https://en.wikipedia.org/wiki/Shiftphone ; https://www.phoronix.com/news/SHIFTphone-8-Linux-Patches

Bootloader and platform policy
- Samsung One UI 8: https://9to5google.com/2025/07/26/samsung-galaxy-one-ui-8-bootloader-unlock/ ; https://www.androidauthority.com/samsung-bootloader-unlocking-disabled-one-ui-8-3581366
- OnePlus ColorOS 16: https://www.notebookcheck.net/OnePlus-tightens-ColorOS-bootloader-unlock-policy-adds-device-quota-and-14-day-expiry-window.1350758.0.html ; https://oxygenupdater.com/article/530/
- Xiaomi HyperOS: https://androidauthority.com/xiaomi-hyperos-bootloader-unlock-3383687 ; https://www.gizmochina.com/2025/01/20/xiaomi-2025-bootloader-unlock-policy-explained/3/ ; official post (not fetched): https://new.c.mi.com/global/post/850671
- Nothing: https://www.thecustomdroid.com/nothing-phone-1-bootloader-unlock-guide
- Sony Open Devices migration: https://community.iode.tech/t/sony-developr-world-site-closes-down/8113 ; https://opendevices.sony.net/posts/sonys-open-devices-program-welcomes-xperia-10-iv-and-10-v
- Fairphone alt-OS: https://support.fairphone.com/hc/articles/9979154556817 ; https://forum.fairphone.com/t/alternative-rom-for-fp6/120247
- Pixel kernel source form: https://www.opensourceforu.com/2026/08/google-makes-pixel-kernel-source-harder-to-access/ ; https://androidauthority.com/google-pixel-kernel-code-forms-3696441/
- Android developer verification: https://itsfoss.com/news/new-android-sideloading-rules ; F-Droid: https://forum.f-droid.org/t/google-will-require-developer-verification-to-install-android-apps-including-sideloading/33123

Regulation, attestation, telephony
- DMA Alphabet interoperability decision: https://digital-markets-act.ec.europa.eu/developer-portal/interoperability/alphabet-specification-proceedings-interoperability-ai-services_en
- CRA (GitHub explainer): https://github.blog/open-source/maintainers/what-the-eus-new-software-legislation-means-for-developers ; LF stewards playbook: https://policy.openssf.org/CRA/stewards-playbook.html ; timeline: https://digital-strategy.ec.europa.eu/en/factpages/cyber-resilience-act-implementation
- Ecodesign 2023/1670: https://www.osnews.com/story/142500/new-eu-rules-mandate-five-years-of-os-updates-for-smartphones-and-tablets/ ; https://heise.de/-10447853
- EU age verification attestation: https://discuss.privacyguides.net/t/eu-age-verification-project-mandates-hardware-bound-attestation/39663 ; https://pasqualepillitteri.it/en/news/9614/eu-age-verification-hardware-attestation-grapheneos
- Play Integrity vs banking (LWN): https://lwn.net/Articles/1004027/
- UBports VoLTE plan (sysmocom): https://ubports.com/blog/1/post/first-steps-in-volte-support-for-ubuntu-touch-3768 ; Qualcomm VoLTE testing: https://forums.ubports.com/post/82716 ; status thread: https://forums.ubports.com/post/77105
- lpac: https://github.com/estkme-group/lpac
