import 'package:flutter/widgets.dart';

// Formatting
class SetTitleIntent extends Intent { const SetTitleIntent(); }
class SetHeaderIntent extends Intent { const SetHeaderIntent(); }
class SetBodyIntent extends Intent { const SetBodyIntent(); }
class SetBulletIntent extends Intent { const SetBulletIntent(); }

// UI Toggles
class ToggleToCIntent extends Intent { const ToggleToCIntent(); }
class ToggleNotesIntent extends Intent { const ToggleNotesIntent(); }
class ToggleToolbarIntent extends Intent { const ToggleToolbarIntent(); }
class OpenSettingsIntent extends Intent { const OpenSettingsIntent(); }
class ToggleFullscreenIntent extends Intent { const ToggleFullscreenIntent(); }

// Zoom
class ZoomInIntent extends Intent { const ZoomInIntent(); }
class ZoomOutIntent extends Intent { const ZoomOutIntent(); }

// Status Bar Peek
class PeekClockIntent extends Intent { const PeekClockIntent(); }
class SetAlarmIntent extends Intent { const SetAlarmIntent(); }
class PeekSessionIntent extends Intent { const PeekSessionIntent(); }
class TogglePomodoroIntent extends Intent { const TogglePomodoroIntent(); }
class ResetPomodoroIntent extends Intent { const ResetPomodoroIntent(); }

// Notes Workflow
class AddNoteIntent extends Intent { const AddNoteIntent(); }
class SaveNoteIntent extends Intent { const SaveNoteIntent(); }
class CycleNoteCategoryIntent extends Intent { const CycleNoteCategoryIntent(); }

// Alignment
class IncreaseWidthIntent extends Intent { const IncreaseWidthIntent(); }
class DecreaseWidthIntent extends Intent { const DecreaseWidthIntent(); }
class ShiftPaperRightIntent extends Intent { const ShiftPaperRightIntent(); }
class ShiftPaperLeftIntent extends Intent { const ShiftPaperLeftIntent(); }
