# Offline CBT (csskabba-portal & Topclass)

Run CBT exams on the school's Wi-Fi with **no internet during the exam**, then upload the
results to csskabba-portal as if the students had written online.

One Windows app, two roles:

| Computer | Role | What it does |
|---|---|---|
| Invigilator / admin PC | **Exam server** | Downloads exams + students from the portal, runs the exam over Wi-Fi, watches students live, uploads results |
| Every exam PC | **Student computer** | Finds the server on the Wi-Fi, students log in and write the exam full-screen |

No PHP, MySQL, Composer or Flutter is installed at the school — the installer contains everything
(the server runs inside the app, data is in SQLite).

```
 csskabba-portal  ⇄ (internet, only before/after)  Exam server PC  ⇄ (Wi-Fi, port 47810)  Student PCs
   /api/offline-cbt/v1                               SQLite + local HTTP server           SQLite copy of answers
```

## Exam day

**Before (with internet)**
1. Portal → *Exams Management → Offline CBT* → **New key** for the admin PC. Copy it.
2. Admin PC → *Portal* tab: portal address + key → *Save & test*.
3. Optional: portal → generate **PINs** for the classes and *Print slips*.
4. Admin PC → *Exams* tab → pick session/term → tick the exams → **Download**.

**During (no internet needed)**
5. Student PCs open the app → the server appears in the list (or type its IP shown in the green bar) → **Connect**.
6. Admin PC → *Exams*: switch the exam **on** when students are seated.
7. Students log in with **admission number + portal password or PIN** and start. The exam is full-screen;
   closing needs the invigilator password.
8. *Live exam* tab: who is writing, on which PC, answered count, time left. Add time, reopen or reset an attempt.

**After (with internet)**
9. *Sync* tab → **Sync now**. Results appear on the portal's exam results like an online sitting.
   Conflicts (student already had an attempt online) wait on the portal's Offline CBT page:
   *Use offline* or *Keep existing*.

## Invigilator tools

- **Pause all / Resume all** — power cut or interruption: every clock stops and answers lock; on resume each student gets the paused time back.
- **Shuffle** (per exam, on by default) — every student gets questions and options in a different order; marking is unaffected.
- **Left-window count** — the exam stays on top; each time a student leaves it (Alt+Tab, Windows key) it is recorded, shown live and uploaded to the portal.
- **Student photos** at login ("Not you? Log out") and in the live list.
- **Practice test** (not recorded, never uploaded) so students learn the screen; reset it any time.
- **Student computers list** — every PC that connected, its address and app version (mismatches in red): a readiness check before the exam.
- **Results report** per exam — Excel (CSV) + printable page, works without internet (`Documents\Offline CBT Results`).
- **Restore a backup** (Settings) — returns the server to any automatic backup; current data is backed up first.
- **Automatic upload** every 5 minutes when internet is available (can be switched off).
- **Login mode** — portal password or PIN, or **PIN only** (no password hashes downloaded); "Remove saved passwords now".
- **Hotspot help** — use the admin PC's Windows Mobile hotspot when there is no router (≈8 computers).
- **Update alerts** — set `OFFLINE_CBT_LATEST_VERSION` / `OFFLINE_CBT_DOWNLOAD_URL` in the portal's `.env`.
- **Calculator per exam** — Off, Basic or Scientific (sin/cos/tan and inverses, log, ln, powers, roots, x!, π, e, Ans, DEG/RAD). Floating and draggable; keyboard input.
- **Sounds** — login, exam start, 5-minute and 1-minute warnings, last-10-seconds tick, time up, submitted, pause/resume, Wi-Fi lost/back; admin alerts on submissions and students leaving the window. Synthesised in the app; switch off in Settings.
- **School branding** — the school's name and logo (from the portal) on every student screen.
- Apple-style design (same colours as the portal's Apple theme); timer ring that changes colour and pulses in the last minute.
- Students: bigger/smaller text; keys A–D choose, ← → move.

## What protects the results

- **Autosave twice**: every answer is written to the student PC's SQLite file at once, then sent to the server.
- **Wi-Fi drop / server off**: the student keeps writing; the timer runs on the PC's own monotonic clock;
  answers and even the final *Submit* are re-sent automatically (also after the PC restarts).
- **Power cut on the server**: SQLite in WAL + FULL sync mode; automatic backup every 10 min and before each sync
  (`%APPDATA%\OfflineCBT\backups`).
- **Server owns the time**: deadline = start + duration (+ time added). 30 s grace; answers a disconnected PC
  saved *before* time ran out are accepted up to 30 min later; nothing after.
- **Frozen exams**: once anyone starts an exam on this server, re-downloading never changes its questions.
- **No duplicates**: every attempt has a UUID; the portal ignores repeats, so *Sync* can be pressed any number of times.
- **No overwrites**: an existing online attempt is never replaced automatically (conflict for the admin).
- **Same marking**: the portal re-marks every uploaded attempt with the same code as the online CBT
  (`App\Services\OfflineCbt\CbtMarker`). Scores shown offline are provisional.
- Correct answers are never sent to student PCs.

## Build the installer (Windows)

**Option A — let GitHub build it (no Windows PC setup needed).**
Push this folder to a GitHub repository, open the **Actions** tab → *Build Windows installer* → **Run workflow**.
After ~15 minutes download `OfflineCBT-installer` from the run. Pushing a tag such as `v1.0.1` also publishes it as a Release.

**Option B — on a Windows PC** with Flutter stable (3.38+), Visual Studio 2022 *Desktop development with C++* and Inno Setup 6:

```powershell
powershell -ExecutionPolicy Bypass -File installer\build_windows.ps1
```

Either way the script: checks the version in `pubspec.yaml` matches `lib/app/services.dart`, creates and brands the
Windows runner (icon, product name), runs the core tests, builds the release and produces
`dist\OfflineCBT-Setup-<version>.exe`. Install that same file on the server and on every student computer — it also
adds the Windows Firewall rules (TCP 47810, UDP 47811). Upgrading keeps all exams, answers and backups (`%APPDATA%\OfflineCBT`).

To release an update: raise `version:` in `pubspec.yaml` and `appVersion` in `lib/app/services.dart`, build, then set
`OFFLINE_CBT_LATEST_VERSION` (and `OFFLINE_CBT_DOWNLOAD_URL`) in each portal's `.env` so computers show "update available".

The app works with **csskabba-portal and Topclass** — each school just enters its own portal address and device key.

SQLite is bundled automatically by the `sqlite3` package's build hook (downloads the prebuilt DLL at build time).

## Code layout

```
lib/                      Flutter UI (Windows desktop)
  app/services.dart       start-up, settings, server start/stop, backups
  ui/server/*             Live exam, Exams, Students, Sync, Portal, Settings
  ui/student/*            Connect, Login, Exam list, Exam (full-screen), Calculator, Done
packages/cbt_core/        all logic, pure Dart (testable without Flutter)
  db.dart                 SQLite schema
  exam_store.dart         import exam packages (freezing running exams)
  exam_service.dart       login (PIN / bcrypt), start/resume, autosave, time limits, submit
  local_server.dart       HTTP API for student PCs
  discovery.dart          UDP auto-discovery on the Wi-Fi
  student_client.dart     student-side session: local cache, retries, offline submit
  portal_client.dart      csskabba-portal API client
  sync_service.dart       idempotent upload
  marker.dart             same marking rules as the portal
  reports.dart            results report (CSV + printable HTML)
  bcrypt.dart             checks Laravel $2y$ password hashes offline
  test/run_all.dart       146 checks: cd packages/cbt_core && dart run test/run_all.dart
installer/                Inno Setup script, build script, icon + wizard images (installer/assets)
.github/workflows/        GitHub Actions: builds the installer on Windows
```

## Portal side (csskabba-portal)

- Migrations `2026_11_18_100000_create_offline_cbt_tables.php` (+ permission *Manage offline-cbt*) and `2026_11_18_110000_add_focus_lost_to_offline_cbt_syncs.php`
- `config/offlinecbt.php` (latest app version + download link for update alerts)
- Exam results page shows an **Offline** label on attempts uploaded from the app
- API `routes/api.php` → `/api/offline-cbt/v1/{ping, exams, package, attempts, attempts/status}` (device-key auth)
- Admin page `/offline-cbt` (device keys, PINs + printable slips, uploaded attempts, conflicts)
- `App\Services\OfflineCbt\{PackageBuilder, AttemptImporter, CbtMarker}`; online submit now uses `CbtMarker` too.
