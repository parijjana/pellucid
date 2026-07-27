# Pellucid

Pellucid is a local-first Markdown writing app for longform fiction. It keeps the manuscript at the center, saves work into ordinary project folders, and offers optional Google Drive backup without hiding the user's files.

The interface uses **Whisper UI**: controls stay visually quiet until they are hovered, focused, or summoned by keyboard shortcut. The goal is a writing surface that feels calm without removing power tools.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/editor.png" alt="Manuscript editor with hidden formatting markers" /></td>
    <td width="50%"><img src="docs/screenshots/table-of-contents.png" alt="Table of contents generated from Markdown headings" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/screenshots/research-notes.png" alt="Research notes panel with categories and links" /></td>
    <td width="50%"><img src="docs/screenshots/snapshots.png" alt="Manuscript snapshots with local and cloud history" /></td>
  </tr>
</table>

<sub>Pellucid on macOS — the Whisper UI keeps controls quiet until you need them.</sub>

<table>
  <tr>
    <td width="50%" align="center"><img src="docs/screenshots/mobile-editor.png" alt="Manuscript editor on mobile" width="270" /></td>
    <td width="50%" align="center"><img src="docs/screenshots/mobile-research-notes.png" alt="Research notes on mobile" width="270" /></td>
  </tr>
</table>

<sub>Android and iOS builds adapt the same manuscript-first layout.</sub>

## Features

- Markdown manuscript editor with hidden formatting markers for headings, bullets, bold, italic, and underline.
- Multi-project dashboard backed by user-owned folders.
- Research notes with categories, bidirectional links, source URLs, and an attribution workflow.
- Table of contents generated from Markdown headings, including per-section word counts.
- Search and replace with match navigation and in-editor highlights.
- Typewriter scrolling, paragraph focus, fullscreen mode, timers, alarms, pomodoro, and writing sprints.
- Daily writing goals and per-project word targets.
- Rolling local snapshots in each project, independent of cloud sync.
- Optional Google Drive backup through a visible `Pellucid Vault` folder.
- PDF and EPUB export.
- Theme presets plus a custom theme designer.
- Desktop-focused UX with mobile adaptations for Android and iOS.

## Quick Start

```powershell
cd writer_app
flutter pub get
flutter run -d windows
```

Use another Flutter device id if you are targeting a different platform.

## Test And Analyze

```powershell
cd writer_app
flutter test
flutter analyze
```

The test suite covers editor behavior, storage, local snapshots, settings, stats, sync, notes, search and replace, shortcuts, focus modes, mobile layout, and the table of contents parser.

## Local Storage

Pellucid asks for a master storage folder. Each project is stored as a normal folder inside it:

```text
<master>/<ProjectName>/
  document.md
  notes.json
  stats.json
  categories.json
  .history/
```

`document.md` is the manuscript. `notes.json` stores research notes and attributions. `stats.json` stores project totals. `categories.json` stores custom note categories. `.history/` contains rolling local manuscript snapshots.

## Google Drive Sync

Google Drive sync is optional. When connected, Pellucid creates a visible `Pellucid Vault` folder in Drive and stores project backups there. The app supports custom OAuth credentials from settings, and the cloud auto-sync interval can be adjusted from the dashboard.

Local autosave and local snapshots work without Google Drive.

## Keyboard Basics

- `Alt + 1`: Toggle table of contents.
- `Alt + 2`: Toggle research notes.
- `Alt + 3`: Toggle formatting toolbar.
- `Alt + 4`: Toggle settings.
- `Alt + 5`: Toggle typewriter scrolling.
- `Alt + 6`: Toggle paragraph focus.
- `Alt + Enter` or `F11`: Toggle fullscreen.
- `Ctrl + F`: Search.
- `Alt + N`: Add a note.
- `Alt + A`: Open attributions.
- `Alt + Shift + S`: Toggle writing sprint.

On macOS, the app uses `Cmd + Opt` for the Alt-based shortcuts.

## Build Targets

The Flutter project includes Windows, macOS, Linux, Android, iOS, and web targets. Windows is the primary desktop distribution target at the moment.

## Public Documentation Policy

Markdown files are ignored by default so local project-management and planning notes do not get committed accidentally. Public documentation is opt-in: only explicitly approved Markdown files, such as this README, should be unignored and committed.
