# SMPTLOG — Amateur Radio Contact Log

> A contact logbook for amateur radio · Android + Windows · local-first · optional encrypted cloud sync

<p>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.47%2B-2F6FED">
  <img alt="Dart" src="https://img.shields.io/badge/Dart-3.13%2B-00B8A9">
  <img alt="Android" src="https://img.shields.io/badge/Android-8.0%20(API%2026)%2B-3DDC84">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%2F11%20x64-0078D4">
  <img alt="License" src="https://img.shields.io/badge/License-Apache_2.0-blue">
</p>

**English** | [中文](README.MD)

---

## What is this

A contact logbook built for radio amateurs to use themselves. Manual entry, ADIF import/export, repeater database, statistics — all **work fully offline**. Only when you explicitly press "Sync" will your log be encrypted and uploaded to **your own** storage.

**No accounts, no server of ours, no telemetry.** Your log stays yours.

| Capability | Description |
|---|---|
| Contact log | Create / edit / delete, four-way filtering, search, sorting, bulk QSL update, duplicate detection |
| ADIF | Import (progress + per-line error report + three duplicate policies), export (with repeater extension fields) |
| Repeaters | Dedicated database, pin favourites, pin a default repeater, auto distance & bearing, reverse lookup of all QSOs via a repeater |
| Overview | Totals, distinct callsigns, repeater usage, last-30-day trend, band/mode distribution |
| Analytics | 24-hour distribution, per-year counts, top-10 callsigns |
| Backup | Full JSON (QSO + repeaters + station profiles), CSV for spreadsheets |
| Cloud sync | EdgeOne Makers Blob **or** Nutstore WebDAV, per-device namespaces with read-time merge, conflicts kept as copies |
| End-to-end encryption | AES-256-GCM, optional, password never leaves the device |
| Responsive | Bottom bar on phones, navigation rail on tablets, collapsible sidebar on desktop |
| Local computation | Maidenhead grid ⇄ lat/lon, great-circle distance, bearing, sunrise/sunset |

---

## Screenshots

| Desktop (Windows 11) | Mobile (Android) |
|---|---|
| ![Logbook · desktop](docs/images/desktop-logbook.png) | ![Logbook · mobile](docs/images/mobile-logbook.jpg) |

**Desktop**: sidebar navigation plus a filter bar; the table supports multi-select, inline edit and delete.
**Mobile**: card list with five bottom tabs (Overview / Log / Repeaters / Analytics / Settings) and a floating action button for quick entry.

---

## Repository layout

```
无线电通联日志助手/
├── SRC/                     Flutter project (android/ + windows/ + lib/)
│   └── smptlog/
│       ├── lib/
│       │   ├── core/        models, SQLite, ADIF, backup, grid & solar math
│       │   ├── sync/        STS credential, COS signature, Blob client, WebDAV, merge engine, crypto, vault
│       │   ├── ui/          pages and shared widgets
│       │   ├── app.dart     responsive shell + shortcuts
│       │   ├── state.dart   global state (provider)
│       │   └── main.dart    entry point
│       ├── android/         package com.smptlog.app, minSdk 26
│       ├── windows/         Windows runner
│       ├── installer/       C# installer / uninstaller sources
│       ├── docs/            data specification
│       └── test/            unit tests (grid / geo / ADIF / dedup)
├── APK/                     Release artifacts
├── EXE/                     Release artifacts
├── TEMP/                    scratch space
└── README.MD / README.en.md
```

---

## Quick start

### Windows

1. Run `EXE/SMPTLOG-Setup-1.1.7.exe`
2. Follow the wizard — **per-user install, no administrator rights needed**
3. Installs to `%LOCALAPPDATA%\Programs\SMPTLOG`
4. Data lives in `%LOCALAPPDATA%\SMPTLOG` (kept on uninstall unless you say otherwise)

### Android

1. Install `APK/SMPTLOG-v1.1.7.apk` (allow "install from unknown sources")
2. Minimum **Android 8.0 (API 26)**
3. Grant the notification permission if prompted (import finished / sync failed notices)

### Optional cloud sync

Three mutually exclusive backends: **Off / EdgeOne / Nutstore**.

- **EdgeOne**: create a Makers project, copy the `projectId` from the project URL (`makers-xxxxxxxxxxxx`), create an API Token under Settings → API Token, then fill both into the app.
- **Nutstore**: email + **application password** (Settings → Security → third-party apps), server `https://dav.jianguoyun.com/dav/`.

The in-app guide (Settings → Cloud sync → "How to get these") walks through every step and lists the common error messages.

---

## Data safety

1. **API tokens and sync passwords are never written into the SQLite database** (the database itself gets synced and exported)
2. **No export file ever contains credentials**
3. Windows stores secrets via **DPAPI** (`CryptProtectData`, current user) in `config/secrets.bin`
4. Android secures them with **Keystore** (AES-256-GCM)
5. Tokens are redacted in any diagnostic output
6. With end-to-end encryption enabled the cloud only ever sees ciphertext — **export a plaintext backup first**, the password cannot be recovered
7. A new device must enter the token again (by design, not a bug)

---

## Usage guide (first five minutes)

### 1. Create a station profile

`Settings → Station profiles → New` — name, your callsign, grid, rig, antenna, power. Create several (handheld / mobile / base) and mark one as default.

> QSO entry then pre-fills callsign, grid, rig and power automatically.

### 2. Create repeater entries (only if you work repeaters)

`Repeaters → New repeater` — name, callsign, downlink, offset, tones, locator. Use the **pin** icon on a card to make it the default repeater.

> Toggling "Via repeater" while logging then fills frequency, mode and tone, and shows the computed uplink frequency live.

### 3. Log a contact

`Log → +` (desktop: "New QSO" at the top right)

- Only the **callsign** is required; the band is derived from the frequency
- Shortcuts for RST (59 / 599) and power (5 W / 25 W / 100 W)
- Desktop has **"Save and continue"**: callsign → Enter → frequency → Enter → RST → Enter saves and returns the cursor to the callsign field

### 4. Import / export

| Action | Where | Notes |
|---|---|---|
| Import ADIF / JSON | Log page, ↓ icon | `.adi` `.adif` `.json`; progress bar and error report |
| Export ADIF | Log page, ↑ icon | Readable by HRD / Log4OM and others |
| Export JSON backup | same | Includes repeaters and station profiles |
| Export CSV | `Settings → Data management` | For spreadsheets |

Duplicate handling on import: **skip / keep all / keep and mark**.

### 5. Multi-device sync (optional)

`Settings → Cloud sync` → fill credentials → **Test connection** → **Save** → **Sync now**. Repeat on the other device; the token is not transferred automatically.

---

## Build from source

### Requirements

| Component | Version | Notes |
|---|---|---|
| Flutter | 3.47.x stable or newer | `flutter doctor` should be clean |
| Dart | 3.13+ | bundled with Flutter |
| Visual Studio | 2022 / 2026 with "Desktop development with C++" **and the Windows 11 SDK** | a missing SDK causes `The current Visual Studio installation is incomplete` |
| JDK | 17 / 21 / 25 | Gradle 9.3 has been verified with JDK 25 |
| Android SDK | platform 36 + build-tools 34+ | install via `sdkmanager` |

Optional in China: set `PUB_HOSTED_URL=https://pub.flutter-io.cn` and `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`.

### Commands

```powershell
cd SRC\smptlog
flutter pub get
flutter test
flutter build apk --release --tree-shake-icons
flutter build windows --release
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
```

`build_installer.ps1` compiles `Installer.cs` / `Uninstaller.cs` with the in-box `csc.exe` and embeds the app archive as a resource, producing a single self-contained installer — no self-extracting wrapper, no batch scripts.

Signing: by default the APK is debug-signed. Generate your own keystore with `keytool`, copy `android/key.properties.example` to `android/key.properties` and fill it in.

> ⚠️ **Back up the keystore and its passwords in two places.** Losing it means the app can never be updated again.

---

## ADIF compatibility

- Standard fields mapped: `CALL` `QSO_DATE` `TIME_ON` `FREQ` `BAND` `MODE` `SUBMODE` `RST_SENT` `RST_RCVD` `TX_PWR` `MY_ANTENNA` `MY_RIG` `QTH` `COUNTRY` `MY_GRID_SQUARE` `GRIDSQUARE` `QSL_SENT` `QSL_RCVD` `COMMENT`
- Repeater data uses underscore-prefixed user fields allowed by the ADIF spec, ignored gracefully by other software:
  `_RELAY_CALL` `_RELAY_FREQ` `_OFFSET` `_CTCSS` `_DCSCODE` `_DMR_CC` `_XREFL` `_WEATHER` `_STATION` `_SMPTL_UUID`
- Digital modes are restored from `MODE:DATA` + `SUBMODE:FT8`
- The parser is fault tolerant: bad fields and bad records are skipped and reported with their offsets

---

## Sync protocol (summary)

```
smptlog/qso/dev/{deviceId}/meta                 rev / count / timestamp per device
smptlog/qso/dev/{deviceId}/shard/{yyyyMM}/{seq}  compressed shards (500 records, gzip)
smptlog/qso/dev/{deviceId}/oplog/{ts}            pending incremental operations
```

- Each device writes **only its own prefix**, which removes write conflicts entirely (the SDK offers no If-Match conditional write)
- `meta` is always read through the **strongly consistent** endpoint to bypass the edge cache
- Merge rule: newest `updatedAt` wins; the losing record is copied into a local `conflicts` table and surfaced in the UI
- Deletes are tombstones, compacted after 90 days

Details in [`SRC/smptlog/docs/数据规范.md`](SRC/smptlog/docs/数据规范.md) (Chinese).

---

## FAQ

**The installer window flashes and disappears on Windows.**
Usually Smart App Control (SAC): check `HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy\VerifiedAndReputablePolicyState` — `1` means enforced. Turn it off under Windows Security → App & browser control → Smart App Control (note: it cannot be re-enabled without reinstalling Windows). Alternatively add the installer to your antivirus allow-list.

**"SMPTLOG is running, file in use" during install.**
Quit the app completely (including the taskbar/tray icon) and run the installer again.

**Cloud sync reports `Invalid project`.**
The `projectId` is wrong — it looks like `makers-60tcjerf0vgq` (older projects use `pages-xxxx`) and is taken from the project page URL. A 12-digit number is the Tencent Cloud APPID, not a project id.

**Cloud sync reports 403 / Access Denied.**
Older builds signed the bucket listing request incorrectly. Upgrade to the latest release.

**Is the token uploaded anywhere?**
No. It is stored locally via DPAPI (Windows) or Keystore (Android) and never enters the database or any export.

**How do I move data to a new device?**
Export a JSON backup on the old device and import it on the new one, or configure the same sync backend on both and press "Sync now".

**Where is the data?**
Windows: `%LOCALAPPDATA%\SMPTLOG\data\smptlog.db`. Android: the app's private directory. Uninstalling asks whether to keep it, defaulting to keep.

**Why is `targetSdk` 36 instead of 37?**
The Android 17 (API 37) platform package has not been published to Google's SDK repository yet. Change the two `36` values in `android/app/build.gradle.kts` once it is available.

**How is a duplicate detected?**
Same normalised callsign + band + mode with a time difference inside the configured window (default **5 minutes**, options 0/5/30/60). Operation suffixes such as `/P` and `/M` are stripped before comparison.

---

## Known limitations

- `targetSdk` is 36 because the API 37 platform package is not published yet
- **Smart App Control** blocks unsigned binaries; the app loads the Microsoft-signed `winsqlite3.dll` on Windows to avoid the related SQLite issue
- **The build path must not contain non-ASCII characters** — Gradle and the Dart AOT compiler fail on such paths
- No map or online lookup built in; everything works offline
- No iOS / macOS / ARM64 builds

---

## Disclaimer

This is a self-hosted tool for radio amateurs and is not affiliated with any radio administration. Responsibility for the accuracy and legality of logged contacts rests with the user. Please follow the radio regulations and amateur radio operating standards of your country or region.

## Code signing policy

**Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).**

All release artifacts are built from this repository by [GitHub Actions](.github/workflows/release.yml). The project is maintained by a single person ([@lezhengqiuyuan](https://github.com/lezhengqiuyuan)), who acts as author, reviewer and signing approver. See **[CODE_SIGNING.md](CODE_SIGNING.md)** for the full policy.

## Privacy policy

> This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.

No local-only operation ever touches the network. The single network activity is the user-initiated sync to a storage service the user configures themselves. No analytics, no ads, no automatic update checks.

## License

Released under the **Apache License 2.0**. See [LICENSE](LICENSE) and the attribution notice in [NOTICE](NOTICE).
