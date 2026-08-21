// Screenshot-harness seed DATA (original fiction) + thin provider subclasses that
// serve seeded display state without touching the real DB, disk, or network.
// Used ONLY by lib/screenshot_main.dart. Never imported by the shipped app.

import 'package:googleapis/drive/v3.dart' as drive;

import 'features/sidebar/providers/note_card.dart';
import 'features/sidebar/providers/notes_provider.dart';
import 'features/sync/providers/sync_provider.dart';
import 'features/sync/models/logical_file.dart';
import 'features/settings/providers/settings_provider.dart';
import 'features/settings/providers/history_provider.dart';
import 'features/settings/providers/project_stats.dart';
import 'features/editor/providers/sprint_controller.dart';
import 'features/editor/providers/editor_provider.dart';

const String kProjectTitle = 'The Salt Coast';

/// Original atmospheric literary fiction. Multiple `##` chapters under one `#`
/// title so the Table of Contents sidebar shows real structure.
const String kManuscript = '''# The Salt Coast

## Chapter One — The Lantern Keeper

The tide came in the colour of old pewter that morning, and Maren Vell climbed the lighthouse stair before the gulls had finished their arguing. Ninety-two steps, worn to shallow bowls by a hundred years of her family's feet. She counted them the way other people counted prayers — not for luck, but for the small certainty of arriving somewhere she already knew.

At the top the lamp waited, cold and patient behind its rings of glass. Her father had tended it for thirty winters and had never once let it fail, not through the storm that took the Merrow or the long dark of the year the herring did not come. Now his hands shook too badly to trim a wick, and so the counting had passed to her, along with everything the counting meant.

She lit the lamp. Below her the town of Alderport turned in its sleep, chimney smoke leaning inland, and far out past the reef the sea went on being the sea — indifferent, enormous, keeping its own accounts.

## Chapter Two — Tidewrack

By noon the beach had given up its usual salvage: a splintered oar, a fishing float green with weed, the pale rope of someone's net cut loose in panic. Maren walked the wrack line with a sack over her shoulder and her eyes on the sand, reading the sea's leavings the way her mother had taught her — every object a sentence, every sentence a small drowned story.

She did not expect the box. It sat above the highest reach of the water, black wood bound in tarnished brass, as though the tide had carried it up and set it down with deliberate care. When she knelt beside it the gulls fell silent all at once, and the silence was worse than any cry.

## Chapter Three — The Drowned Bell

There is a bell beneath Alderport harbour. The old people say it rang once, the night the town made its bargain with the water, and that it has been ringing ever since in a register too low for living ears. You do not hear the drowned bell. You feel it — in the ache of a bad tooth, in the way milk turns early, in dreams of a door you cannot quite reach.

Maren had never believed it. She believed in the lamp, in the ninety-two steps, in the weight of a full net and the arithmetic of a lean season. But that night, with the black box unopened on her table and the sea unusually still, she lay awake and felt something vast and patient turning over in its sleep, far below.

## Chapter Four — What the Gulls Knew

Her father was awake when she came down, sitting by the banked fire with his ruined hands folded in his lap. He did not ask about the box. He looked at it once, and then away, and in that single glance Maren understood that he had been waiting for it — had been waiting, perhaps, her whole life.

"The sea keeps what it is owed," he said. "And it always, always collects." Outside, one by one, the gulls lifted from the rooftops and flew inland, away from the water, the way they only ever did before a storm no instrument had yet learned to measure.
''';

/// Codex / worldbuilding cards for the Notes & Research sidebar.
List<NoteCard> seedNotes() => [
      NoteCard(
        title: 'Maren Vell',
        category: 'people',
        content:
            'Lighthouse keeper\'s daughter, 24. Practical, guarded, allergic to superstition — which makes her the worst possible person to inherit a family bargain. Counts the 92 stair-steps to steady herself.',
      ),
      NoteCard(
        title: 'Alderport',
        category: 'places',
        content:
            'A fading harbour town built on a reef and a rumour. Herring economy collapsing. The lighthouse (the Vell family\'s charge) is the only thing the town agrees still matters.',
      ),
      NoteCard(
        title: 'The Drowned Bell',
        category: 'events',
        content:
            'The bargain-relic beneath the harbour. Rings below the threshold of hearing. Payment is implied but never named until Ch. 4. Recurring motif: felt, not heard.',
      ),
      NoteCard(
        title: 'The Black Box',
        category: 'general',
        content:
            'Tarnished brass on black wood. The sea "returns" it deliberately. Do NOT reveal contents before Act II — let the gulls\' silence do the work.',
      ),
    ];

/// Recent cloud revisions for the version-history dialog. Constructed in-memory —
/// no Google Drive call is made.
List<drive.Revision> seedRevisions() {
  DateTime at(int day, int h, int m) => DateTime(2026, 7, day, h, m);
  final stamps = [
    at(26, 9, 14),
    at(26, 7, 2),
    at(25, 22, 48),
    at(25, 16, 30),
    at(24, 20, 11),
    at(23, 8, 55),
  ];
  final out = <drive.Revision>[];
  for (var i = 0; i < stamps.length; i++) {
    out.add(drive.Revision()
      ..id = 'rev${i + 1}'
      ..modifiedTime = stamps[i].toUtc());
  }
  // Dialog reverses the list, treating the tail as newest, so seed oldest-first.
  return out.reversed.toList();
}

/// Serves seeded codex cards without reading project files.
class ScreenshotNotesProvider extends NotesProvider {
  final List<NoteCard> _seed;
  ScreenshotNotesProvider(this._seed);
  @override
  List<NoteCard> get cards => List.unmodifiable(_seed);
}

/// Logged-in, idle sync with seeded revisions. Every network method is a no-op.
class ScreenshotSyncProvider extends SyncProvider {
  final List<drive.Revision> _seed;
  ScreenshotSyncProvider(this._seed);
  @override
  bool get isLoggedIn => true;
  @override
  SyncStatus get status => SyncStatus.idle;
  @override
  List<drive.Revision> get history => _seed;
  @override
  Future<void> loadHistory(String projectName, LogicalFile fileName) async {}
  @override
  Future<void> refreshLastSynced(String projectName, LogicalFile fileName) async {}
  @override
  Future<String?> getLatestContent({required String projectName, required LogicalFile fileName}) async => null;
  @override
  Future<void> syncCurrentFile({required String projectName, required LogicalFile fileName, required String content}) async {}
}

/// Realistic session/goal/timer display values. No DB writes (base setters are
/// never called; only getters are overridden).
class ScreenshotSettingsProvider extends SettingsProvider {
  @override
  String? get currentProjectName => kProjectTitle;
  @override
  bool get clockEnabled => true;
  @override
  bool get currentSessionEnabled => true;
  @override
  bool get targetSessionEnabled => true;
  @override
  Duration get currentSessionTime => const Duration(hours: 1, minutes: 47);
  @override
  Duration get targetSessionTime => const Duration(hours: 2, minutes: 0);
  @override
  bool get focusTimerEnabled => true;
  @override
  bool get isPomodoroActive => true;
  @override
  Duration get pomodoroRemaining => const Duration(minutes: 18, seconds: 32);
  @override
  bool get batteryGuardEnabled => true;
  @override
  bool get tocWordCountsEnabled => true;
  @override
  bool get codexLinkingEnabled => true;
  @override
  bool get spellCheckEnabled => false; // no red squiggles in shots
  @override
  int get dailyWordGoal => 1500;
  @override
  bool get hasDailyWordGoal => true;
}

/// Populated writing stats so any stats surface reads real numbers.
class ScreenshotHistoryProvider extends HistoryProvider {
  @override
  ProjectStats get currentProjectStats => ProjectStats(
        totalWordCount: 61840,
        totalTimeSpent: const Duration(hours: 41, minutes: 12),
        wordGoal: 80000,
      );
  @override
  DailyStats? get todayStats => DailyStats(
        date: '2026-07-26',
        editorTime: const Duration(hours: 1, minutes: 47),
        notesTime: const Duration(minutes: 22),
        wordCountDelta: 1240,
      );
}

/// An in-progress writing sprint (active, mid-countdown).
class ScreenshotSprintController extends SprintController {
  @override
  bool get isActive => true;
  @override
  Duration get remaining => const Duration(minutes: 12, seconds: 8);
}

/// Serves the seeded manuscript and a per-target page width without persisting
/// anything (base setters would write to the real settings DB — never called).
class ScreenshotEditorProvider extends EditorProvider {
  final String _seedContent;
  final double _pageWidth;
  ScreenshotEditorProvider({required String content, required double pageWidth})
      : _seedContent = content,
        _pageWidth = pageWidth;
  @override
  String get content => _seedContent;
  @override
  double get pageWidth => _pageWidth;
}
