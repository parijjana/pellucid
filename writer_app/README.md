# Pellucid Flutter App

This directory contains the Flutter application for Pellucid, a local-first Markdown writing app for longform fiction.

Pellucid uses **Whisper UI**: controls stay visually quiet until hovered, focused, or summoned by keyboard shortcut. The writing surface stays calm while project tools, notes, search, snapshots, sync, and export remain close at hand.

## Run

```powershell
flutter pub get
flutter run -d windows
```

Use another Flutter device id for macOS, Linux, Android, iOS, or web.

## Test

```powershell
flutter test
flutter analyze
```

## App Data

Projects are stored in a user-selected master folder:

```text
<master>/<ProjectName>/
  document.md
  notes.json
  stats.json
  categories.json
  .history/
```

Google Drive sync is optional and uses a visible `Pellucid Vault` folder. Local autosave and local snapshots work without cloud sync.

For the full project overview, see the root `README.md`.
