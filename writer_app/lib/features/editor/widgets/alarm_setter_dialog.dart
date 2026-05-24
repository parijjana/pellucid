import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../../settings/providers/settings_provider.dart';

class AlarmSetterDialog extends StatefulWidget {
  const AlarmSetterDialog({super.key});

  @override
  State<AlarmSetterDialog> createState() => _AlarmSetterDialogState();
}

class _AlarmSetterDialogState extends State<AlarmSetterDialog> {
  late TextEditingController _hourController;
  late TextEditingController _minuteController;
  late FocusNode _hourFocusNode;
  late FocusNode _minuteFocusNode;
  late FocusNode _clearFocusNode;
  late FocusNode _cancelFocusNode;
  late FocusNode _saveFocusNode;

  @override
  void initState() {
    super.initState();

    _hourFocusNode = FocusNode(
      debugLabel: 'HourFocus',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _incrementHour(1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _incrementHour(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _minuteFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _saveAlarm();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _minuteFocusNode = FocusNode(
      debugLabel: 'MinuteFocus',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _incrementMinute(1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _incrementMinute(-1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _hourFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            final hasClear = context.read<SettingsProvider>().alarmTime != null;
            if (hasClear) {
              _clearFocusNode.requestFocus();
            } else {
              _cancelFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _saveAlarm();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _clearFocusNode = FocusNode(
      debugLabel: 'ClearFocus',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _minuteFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _cancelFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _cancelFocusNode = FocusNode(
      debugLabel: 'CancelFocus',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final hasClear = context.read<SettingsProvider>().alarmTime != null;
            if (hasClear) {
              _clearFocusNode.requestFocus();
            } else {
              _minuteFocusNode.requestFocus();
            }
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _saveFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    _saveFocusNode = FocusNode(
      debugLabel: 'SaveFocus',
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _cancelFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    final settings = context.read<SettingsProvider>();
    final initialTime = settings.alarmTime ?? DateTime.now().add(const Duration(hours: 1));

    _hourController = TextEditingController(text: initialTime.hour.toString().padLeft(2, '0'));
    _minuteController = TextEditingController(text: initialTime.minute.toString().padLeft(2, '0'));

    _hourFocusNode.addListener(() {
      if (_hourFocusNode.hasFocus) {
        _hourController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _hourController.text.length,
        );
      }
    });

    _minuteFocusNode.addListener(() {
      if (_minuteFocusNode.hasFocus) {
        _minuteController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _minuteController.text.length,
        );
      }
    });

    // Auto-focus Hour on open
    _hourFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourFocusNode.dispose();
    _minuteFocusNode.dispose();
    _clearFocusNode.dispose();
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }

  void _incrementHour(int delta) {
    int val = int.tryParse(_hourController.text) ?? 0;
    val = (val + delta) % 24;
    if (val < 0) val += 24;
    _hourController.text = val.toString().padLeft(2, '0');
    _hourController.selection = TextSelection(baseOffset: 0, extentOffset: _hourController.text.length);
  }

  void _incrementMinute(int delta) {
    int val = int.tryParse(_minuteController.text) ?? 0;
    val = (val + delta) % 60;
    if (val < 0) val += 60;
    _minuteController.text = val.toString().padLeft(2, '0');
    _minuteController.selection = TextSelection(baseOffset: 0, extentOffset: _minuteController.text.length);
  }

  void _saveAlarm() {
    int? hour = int.tryParse(_hourController.text);
    int? minute = int.tryParse(_minuteController.text);

    if (hour == null || hour < 0 || hour > 23 || minute == null || minute < 0 || minute > 59) {
      return; // Invalid time
    }

    final now = DateTime.now();
    final alarm = DateTime(now.year, now.month, now.day, hour, minute);
    
    final settings = context.read<SettingsProvider>();
    settings.setAlarm(alarm);
    Navigator.pop(context);
  }

  void _clearAlarm() {
    final settings = context.read<SettingsProvider>();
    settings.clearAlarm();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>().currentTheme;
    final settings = context.watch<SettingsProvider>();
    final hasActiveAlarm = settings.alarmTime != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 330,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: theme.sidebarColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: theme.sidebarShadows,
            border: Border.all(color: theme.foregroundColor.withValues(alpha: 0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SET ALARM',
                style: TextStyle(
                  color: theme.foregroundColor.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _TimeInputField(
                    controller: _hourController,
                    focusNode: _hourFocusNode,
                    label: 'HOURS',
                    theme: theme,
                    onChanged: (text) {
                      if (text.length == 2) {
                        _minuteFocusNode.requestFocus();
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0).copyWith(bottom: 16),
                    child: Text(
                      ':',
                      style: TextStyle(
                        color: theme.foregroundColor.withValues(alpha: 0.5),
                        fontSize: 32,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _TimeInputField(
                    controller: _minuteController,
                    focusNode: _minuteFocusNode,
                    label: 'MINUTES',
                    theme: theme,
                    onChanged: (text) {
                      if (text.length == 2) {
                        _saveFocusNode.requestFocus();
                      }
                    },
                  ),
                ],
              ),
              if (hasActiveAlarm) ...[
                const SizedBox(height: 8),
                Text(
                  'Active: ${settings.alarmTime!.hour.toString().padLeft(2, '0')}:${settings.alarmTime!.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: theme.foregroundColor.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hasActiveAlarm) ...[
                    _DialogButton(
                      label: 'CLEAR',
                      focusNode: _clearFocusNode,
                      onPressed: _clearAlarm,
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _DialogButton(
                    label: 'CANCEL',
                    focusNode: _cancelFocusNode,
                    onPressed: () => Navigator.pop(context),
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _DialogButton(
                    label: 'SAVE',
                    focusNode: _saveFocusNode,
                    onPressed: _saveAlarm,
                    theme: theme,
                    isPrimary: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final ValueChanged<String>? onChanged;
  final WriterTheme theme;

  const _TimeInputField({
    required this.controller,
    required this.focusNode,
    required this.label,
    this.onChanged,
    required this.theme,
  });

  @override
  State<_TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<_TimeInputField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasFocus = widget.focusNode.hasFocus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 70,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.theme.foregroundColor.withValues(alpha: hasFocus ? 0.05 : 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFocus
                  ? widget.theme.foregroundColor.withValues(alpha: 0.5)
                  : widget.theme.foregroundColor.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            cursorColor: widget.theme.foregroundColor.withValues(alpha: 0.3),
            style: TextStyle(
              color: widget.theme.foregroundColor,
              fontSize: 32,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: TextStyle(
            color: widget.theme.foregroundColor.withValues(alpha: hasFocus ? 0.5 : 0.2),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

class _DialogButton extends StatefulWidget {
  final String label;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final WriterTheme theme;
  final bool isPrimary;

  const _DialogButton({
    required this.label,
    required this.focusNode,
    required this.onPressed,
    required this.theme,
    this.isPrimary = false,
  });

  @override
  State<_DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<_DialogButton> {
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || widget.focusNode.hasFocus;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isPrimary
              ? (active ? widget.theme.foregroundColor : widget.theme.foregroundColor.withValues(alpha: 0.1))
              : (active ? widget.theme.foregroundColor.withValues(alpha: 0.08) : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? widget.theme.foregroundColor.withValues(alpha: widget.isPrimary ? 1.0 : 0.4)
                : widget.theme.foregroundColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: InkWell(
          focusNode: widget.focusNode,
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              widget.label,
              style: TextStyle(
                color: widget.isPrimary
                    ? (active ? widget.theme.backgroundColor : widget.theme.foregroundColor)
                    : widget.theme.foregroundColor.withValues(alpha: active ? 1.0 : 0.6),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
