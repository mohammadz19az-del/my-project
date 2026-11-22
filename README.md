# Tesla.org

Cross-platform (Windows 10/11 and Android) messaging **account and campaign manager** built with
Flutter/Dart, SQLite (`sqflite` + raw SQL + migrations), Riverpod and GoRouter.
Everything is stored on your device; there is no Tesla.org server.

> **Verification status — read this first.** All source code is written, but it has **not been
> compiled, analysed, tested or built** by the author: the environment where it was generated had no
> Flutter/Dart SDK. The SQL (schema, triggers, migrations, report queries) *was* executed against real
> SQLite, and the Jalali date algorithm was checked against known dates. Expect that the first
> `flutter analyze` / `flutter test` run on your machine may report small errors; send them back and
> they will be fixed. Nothing has been tested against live Telegram or WhatsApp accounts.

## What is in it
| Area | State |
|---|---|
| Dashboard, Accounts, Messages, Group Links, Campaigns, Activity Reports, Settings | all implemented (no placeholders) |
| Telegram | **real**, official Bot API (bots only) |
| WhatsApp | **real**, official Cloud API (needs Meta Business setup; templates outside the 24 h window) |
| Rubika, Soroush | **mock only** — no official API verified; nothing is ever sent |
| Persian (RTL) + English, dark/light, accent colors, reduced motion, Jalali dates | implemented |
| Backup / restore, CSV / JSON export, in-app notices | implemented |

See `docs/GENERATION_PROGRESS.md` for the exact feature list and limitations, and
`docs/DOCUMENTATION.md` for architecture, security and the user guide.

## Install and run (Windows)
1. Install **Flutter** (stable channel, Dart ≥ 3.4) from https://docs.flutter.dev/get-started/install/windows
   and, for the Windows app, **Visual Studio 2022** with the *Desktop development with C++* workload.
   For Android also install **Android Studio** (Android SDK) and run `flutter doctor` until it is green.
2. Unzip this project, open PowerShell in the folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
   ```
   It generates the native `android/` and `windows/` folders, sets Android `minSdk 23`, adds the INTERNET
   permission, then runs `flutter pub get`, `flutter analyze` and `flutter test`.
3. Run: `flutter run -d windows` (or pick an Android device/emulator with `flutter run`).
4. Release builds: `scripts\setup.ps1 -Build`, or manually
   `flutter build windows --release` → `build\windows\x64\runner\Release\` (copy the whole folder) and
   `flutter build apk --release` → `build\app\outputs\flutter-apk\app-release.apk` (sideload; it is
   debug-signed, which is fine for personal use but not for Google Play).

### Manual equivalent of the script
```bash
flutter create --platforms=windows,android --project-name tesla_org --org org.teslaorg .
del test\widget_test.dart            # sample test created by flutter create
# android/app/build.gradle(.kts): set minSdk = 23 ; AndroidManifest.xml: add
#   <uses-permission android:name="android.permission.INTERNET"/> before <application
flutter pub get && flutter analyze && flutter test
```

## First use
Add a Telegram bot (token from @BotFather) or WhatsApp Cloud API number → **Connect** → write templates →
add destinations that consented → create a campaign → Start. Keep the app open while it runs.
The in-app **Settings → User guide** explains each step in English and Persian.

## Optional: Persian font
The platform font (Segoe UI / Roboto) renders Persian correctly. To bundle **Vazirmatn** (SIL OFL):
download it, put the `.ttf` files in `assets/fonts/`, add to `pubspec.yaml`
```yaml
flutter:
  fonts:
    - family: Vazirmatn
      fonts:
        - asset: assets/fonts/Vazirmatn-Regular.ttf
        - asset: assets/fonts/Vazirmatn-Bold.ttf
          weight: 700
```
and set `fontFamily: 'Vazirmatn'` in `ThemeData(...)` inside `lib/core/theme/app_theme.dart`.
(Fonts could not be downloaded or bundled when this project was generated.)

## Project layout
`lib/app` bootstrap, router, shell · `lib/core` database, errors, localization, security, storage, theme,
widgets · `lib/features/<feature>` (accounts, campaigns, dashboard, groups, messages, reports, settings) ·
`lib/integrations/common` adapters · `lib/shared` models/enums · `test/` · `docs/` · `scripts/`.

## Build without installing anything (GitHub Actions)
1. Create a free account at github.com and a new **private** repository.
2. Upload the *contents* of this folder (including the hidden `.github` folder) to it.
3. Open the **Actions** tab → *Build Tesla.org* → **Run workflow**.
4. After ~10-15 minutes open the finished run and download **tesla-windows-installer** (run `Tesla.org-Setup.exe`),
   optionally **tesla-windows-portable** (folder, run `tesla_org.exe`) and **tesla-android** (`app-release.apk`, sideload it). Analyze/test results appear in the run log.
If the build fails, copy the red error text from the log and send it to the maintainer.
