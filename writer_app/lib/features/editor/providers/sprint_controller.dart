// @trace FEAT-20260705-000000-0006
// Description: Writing sprint timer. A pomodoro variant that reports the words
// written during the sprint using the existing HistoryProvider word delta.

import 'dart:async';
import 'package:flutter/foundation.dart';

class SprintController extends ChangeNotifier {
  static const Duration defaultDuration = Duration(minutes: 25);

  Duration _duration = defaultDuration;
  Duration _remaining = defaultDuration;
  bool _isActive = false;
  int _baseline = 0;
  int? _lastSprintWords;
  Timer? _timer;
  int Function()? _wordSource;

  bool get isActive => _isActive;
  Duration get remaining => _remaining;

  /// Words written during the most recently completed sprint (may be negative).
  /// Null until a sprint has finished, and reset when a new sprint starts.
  int? get lastSprintWords => _lastSprintWords;

  /// Starts a sprint, capturing the current word delta as the baseline via
  /// [currentWords]. The same source is read again on completion to compute the
  /// difference — no separate word tracking is introduced.
  void start({required int Function() currentWords, Duration? duration}) {
    if (_isActive) return;
    _duration = duration ?? _duration;
    _remaining = _duration;
    _wordSource = currentWords;
    _baseline = currentWords();
    _lastSprintWords = null;
    _isActive = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining.inSeconds > 0) {
        _remaining -= const Duration(seconds: 1);
        notifyListeners();
      } else {
        _finish();
      }
    });
    notifyListeners();
  }

  /// Ends the sprint early; still reports the words written so far.
  void stop() {
    if (!_isActive) return;
    _finish();
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _lastSprintWords = (_wordSource?.call() ?? _baseline) - _baseline;
    _remaining = _duration;
    notifyListeners();
  }

  /// Dismisses the last result from the ghost surface.
  void clearResult() {
    if (_lastSprintWords == null) return;
    _lastSprintWords = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
