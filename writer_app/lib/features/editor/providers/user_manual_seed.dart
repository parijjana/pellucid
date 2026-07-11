// Description: Static seed content for the auto-generated "User Manual" project
// (manuscript body + starter notes). Kept out of storage_service.dart per the
// 200-line file mandate; this is data, not I/O logic.

import 'dart:convert';

const String userManualContent = '''# PELLUCID USER MANUAL

Welcome to Pellucid, a distraction-free writing environment designed to let your words breathe. Every interface element is a "Ghost" - barely visible until you need it - ensuring your manuscript remains the center of your universe.

## CHAPTER 1: CORE DESIGN PRINCIPLES

- Ghost UI: All interface overlays, such as the status bar and the project title, default to a low 20% opacity. Simply hover over them with your cursor to bring them into full focus.
- Distraction Free: There are no text boxes, menus, or scrollbars crowding your screen. Focus on writing.
- Master Projects: All projects are saved in folders inside your Master Storage Directory. Setting a master directory automatically seeds this User Manual as a project for you.

## CHAPTER 2: CLOUD SYNCHRONIZATION

Your work is automatically backed up to Google Drive. This isn't a "Black Box" - Pellucid creates a visible folder called "Pellucid Vault" in your Drive so you always own your data.

How to Connect:
1. Open Settings using the shortcut key Alt + 4 (Cmd + Opt + 4 on macOS).
2. Select a Master Storage Folder on your local machine.
3. Click the CONNECT button under Google Drive Backup.
4. Complete the authorization inside your web browser. Your "Pellucid Vault" folder will be created and synchronized automatically.

## CHAPTER 3: KEYBOARD SHORTCUTS

Pellucid is designed to be operated entirely from your keyboard, letting you write and navigate without touching your mouse.

Double-tap the Alt key (left or right Alt) at any time to display a temporary overlay showing the shortcuts helper.

### Global Interface Toggles:
- Alt + 1: Toggle Table of Contents (Left Sidebar) / Cmd + Opt + 1 on macOS
- Alt + 2: Toggle Research Notes (Right Sidebar) / Cmd + Opt + 2 on macOS
- Alt + 3: Toggle Formatting Toolbar / Cmd + Opt + 3 on macOS
- Alt + 4: Toggle Settings / Dashboard / Cmd + Opt + 4 on macOS
- Alt + Enter: Toggle Fullscreen Mode (F11 also works) / Cmd + Opt + Enter on macOS

### Text Formatting:
- Alt + T: Format current line as Title / Cmd + Opt + T on macOS
- Alt + H: Format current line as Header / Cmd + Opt + H on macOS
- Alt + G: Format current line as Body text / Cmd + Opt + G on macOS
- Alt + L: Format current line as Bullet point / Cmd + Opt + L on macOS
- Ctrl + B: Toggle Bold on selection / Cmd + B on macOS
- Ctrl + I: Toggle Italic on selection / Cmd + I on macOS

### Notes and Attribution Workflow:
- Alt + N: Create a new Research Note / Cmd + Opt + N on macOS
- Alt + M: Cycle category of the currently open Note / Cmd + Opt + M on macOS
- Alt + B: Save and Close the current Note / Cmd + Opt + B on macOS
- Alt + A: Open or create the Attributions Note directly / Cmd + Opt + A on macOS
- Arrow Keys: Navigate between notes when the Notes sidebar is active
- Enter / Return: Open the selected note or Attribution panel from the sidebar

### Status Bar Peek Controls:
- Alt + C: Peek Clock / Dismiss Alarm / Cmd + Opt + C on macOS
- Alt + Shift + A: Set Alarm / Cmd + Opt + Shift + A on macOS
- Alt + S: Peek Session stats / Cmd + Opt + S on macOS
- Alt + P: Start / Pause Pomodoro Timer / Cmd + Opt + P on macOS
- Alt + Shift + P: Reset Pomodoro Timer / Cmd + Opt + Shift + P on macOS

### Physical Page Alignment:
- Alt + Left Arrow / Right Arrow: Adjust page width / Cmd + Opt + Left / Right on macOS
- Alt + Shift + Left Arrow / Shift + Right Arrow: Shift page position horizontally / Cmd + Opt + Shift + Left / Right on macOS

### Search and Match Navigation:
- Ctrl + F: Toggle Search / Cmd + F on macOS
- Enter: Navigate to the next match when typing a query
- Up / Down arrow buttons (in search popup): Cycle through matches in the editor
- Escape: Dismiss search panel and clear highlights

## CHAPTER 4: SEARCH & NAVIGATIONAL HIGHLIGHTS

Pellucid includes a real-time global search system that highlights matching terms across the editor, Table of Contents (TOC) sidebar, and Research Notes.

Key Features:
- Bottom Command Palette: Pressing Ctrl + F (Cmd + F on macOS) displays a glassmorphic search panel floating at the bottom of your screen.
- Persistent Highlights: The search box and highlights remain active even when you interact with other panels (such as clicking on chapters in the TOC or browsing your notes).
- Match Navigation: Step through matches using the up/down arrows in the search box or by pressing Enter in the search field. The editor will automatically scroll to center the active match with a distinct orange highlight.
- Dismissal: Click the close button inside the search box or press Escape to close the panel and remove the highlights.
''';

String userManualNotesJson() => jsonEncode([
      {
        "id": "note-attribution",
        "title": "Attributions",
        "content": "",
        "category": "general",
        "connections": ["note-general"],
        "isAttribution": true,
        "sourceUrl": "https://www.overengineeredhobbies.dev",
        "attributionItems": [
          {
            "id": "item-web",
            "text": "www.overengineeredhobbies.dev",
            "connections": ["note-general"]
          }
        ],
        "attributionType": "bullet"
      },
      {
        "id": "note-general",
        "title": "Welcome Note",
        "content": "This is a general welcome note. It connects to the people note and places note.",
        "category": "general",
        "connections": ["note-attribution", "note-people", "note-places"],
        "isAttribution": false,
        "sourceUrl": null,
        "attributionItems": null,
        "attributionType": "bullet"
      },
      {
        "id": "note-people",
        "title": "Overengineered Hobbies Team",
        "content": "The developers behind Pellucid. This note connects back to the general note and the events note.",
        "category": "people",
        "connections": ["note-general", "note-events"],
        "isAttribution": false,
        "sourceUrl": null,
        "attributionItems": null,
        "attributionType": "bullet"
      },
      {
        "id": "note-places",
        "title": "The Digital Realm",
        "content": "Where all distraction-free writing happens. This note connects back to the general note and the events note.",
        "category": "places",
        "connections": ["note-general", "note-events"],
        "isAttribution": false,
        "sourceUrl": null,
        "attributionItems": null,
        "attributionType": "bullet"
      },
      {
        "id": "note-events",
        "title": "Launch of Pellucid",
        "content": "Pellucid is launched! This note connects to the people note and places note.",
        "category": "events",
        "connections": ["note-people", "note-places"],
        "isAttribution": false,
        "sourceUrl": null,
        "attributionItems": null,
        "attributionType": "bullet"
      }
    ]);
