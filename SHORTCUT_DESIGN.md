# Pellucid Editor: Keyboard Navigation Scheme (Finalized)

This document outlines the finalized keyboard shortcuts for Pellucid. 

## Design Principles
1. **Modifier Logic:**
   - **Windows/Linux:** Uses `Alt` for UI actions. Safe because Pellucid has no standard menu bar.
   - **macOS:** Uses `Cmd (⌘) + Opt (⌥)` for UI actions. This avoids conflicts with the native `Opt + [Key]` special character symbols (e.g., `Opt + s` is `ß`), which is critical for writers.
2. **Standard Compatibility:** Supports standard text commands and "old-school" variants (e.g., `Ctrl+Insert`).
3. **Ghost Interaction:** Triggering a shortcut will visually brighten the corresponding "Ghost UI" element (100% opacity) and perform the action.

---

### 1. Standard Text & Formatting
Supports all standard OS text interactions.

| Feature | Windows / Linux | macOS |
| :--- | :--- | :--- |
| Toggle Bold | `Ctrl + B` | `Cmd + B` |
| Toggle Italic | `Ctrl + I` | `Cmd + I` |
| Copy | `Ctrl + C` OR `Ctrl + Insert` | `Cmd + C` |
| Paste | `Ctrl + V` OR `Shift + Insert` | `Cmd + V` |
| Cut | `Ctrl + X` | `Cmd + X` |
| Undo / Redo | `Ctrl + Z` / `Ctrl + Y` | `Cmd + Z` / `Cmd + Shift + Z` |

---

### 2. UI Panel Toggles (Adjacent Number Row)
Major layout panels are mapped to neighboring number keys.

| Widget | Feature | Windows / Linux | macOS |
| :--- | :--- | :--- | :--- |
| **Table of Contents** | Toggle Left Sidebar | `Alt + 1` | `Cmd + Opt + 1` |
| **Notes Sidebar** | Toggle Right Sidebar | `Alt + 2` | `Cmd + Opt + 2` |
| **Formatting Bar** | Toggle Floating Toolbar | `Alt + 3` | `Cmd + Opt + 3` |
| **Dashboard** | Open Settings | `Alt + 4` | `Cmd + Opt + 4` OR **`Cmd + ,`** (standard macOS Preferences) |
| **Editor** | Toggle Typewriter Scrolling | `Alt + 5` | `Cmd + Opt + 5` |
| **Editor** | Toggle Paragraph Focus | `Alt + 6` | `Cmd + Opt + 6` |
| **Fullscreen** | Toggle Fullscreen | `F11` OR **`Alt + Enter`** | **`Cmd + Ctrl + F`** OR `Cmd + Opt + Enter` |

---

### 3. Status Bar & Cloud
Interaction with the "Ghost" widgets at the bottom.

| Widget | Feature | Windows / Linux | macOS |
| :--- | :--- | :--- | :--- |
| **Clock** | "Peek" Time (Ghost Focus) | `Alt + C` | `Cmd + Opt + C` |
| **Clock** | Set / Dismiss Alarm | `Alt + Shift + A` | `Cmd + Opt + Shift + A` |
| **Session** | "Peek" Session Timer | `Alt + S` | `Cmd + Opt + S` |
| **Pomodoro** | Start / Pause Timer | `Alt + P` | `Cmd + Opt + P` |
| **Pomodoro** | Reset Timer | `Alt + Shift + P` | `Cmd + Opt + Shift + P` |

---

### 4. Research Notes Workflow
Quick management of notes without leaving the keyboard.

| Feature | Windows / Linux | macOS |
| :--- | :--- | :--- |
| Add New Note | `Alt + N` | `Cmd + Opt + N` |
| **Save / Commit Note** | **`Alt + B`** | **`Cmd + Opt + B`** |
| Cycle Note Category | `Alt + M` | `Cmd + Opt + M` |
| Open / Create Attributions | `Alt + A` | `Cmd + Opt + A` |

---

### 5. Alignment Bar (Physical Paper Movement)
Moving the writing area on the screen.

| Feature | Windows / Linux | macOS |
| :--- | :--- | :--- |
| Increase Page Width | `Alt + Right Arrow` | `Cmd + Opt + Right` |
| Decrease Page Width | `Alt + Left Arrow` | `Cmd + Opt + Left` |
| Shift Paper Right | `Alt + Shift + Right`| `Cmd + Opt + Shift + Right` |
| Shift Paper Left | `Alt + Shift + Left` | `Cmd + Opt + Shift + Left` |

---

## Conflict Verification
- **System:** `Alt+F4`, `Alt+Tab`, and macOS `Cmd+Space` are avoided.
- **Text Entry:** `Alt` on Windows is safe in a menu-less app. `Cmd+Opt` on Mac is safe from special character triggers.
- **Redundancy:** Fullscreen now has a "Media Key Safe" alternative (`Alt + Enter`).
- **Settings Awareness:** Shortcuts will be ignored if the corresponding widget is disabled in Settings.
