// Description: The macOS Format menu, with checkmarks for the formatting at
// the caret (backlog item 25). Items invoke the same intents as the editor
// shortcuts and toolbar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caret_formatting.dart';
import 'shortcuts.dart';

/// Same convention as the spell-check item: a leading tick when on.
String checkedLabel(String label, bool on) => on ? '✓ $label' : '   $label';

void _invoke(Intent intent) {
  final contextNode = FocusManager.instance.primaryFocus?.context;
  if (contextNode != null) Actions.maybeInvoke(contextNode, intent);
}

List<PlatformMenuItem> formatMenuItems(FormattingState f) => [
      PlatformMenuItem(
        label: checkedLabel('Title', f.block == BlockStyle.title),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyT, alt: true, meta: true),
        onSelected: () => _invoke(const SetTitleIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Heading', f.block == BlockStyle.heading),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyE, alt: true, meta: true),
        onSelected: () => _invoke(const SetHeaderIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Subheading', f.block == BlockStyle.subheading),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyJ, alt: true, meta: true),
        onSelected: () => _invoke(const SetSubheadingIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Body', f.block == BlockStyle.body && f.list == ListStyle.none),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyG, alt: true, meta: true),
        onSelected: () => _invoke(const SetBodyIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Bullet', f.list == ListStyle.bullet),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyL, alt: true, meta: true),
        onSelected: () => _invoke(const SetBulletIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Quote', f.block == BlockStyle.quote),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyQ, alt: true, meta: true),
        onSelected: () => _invoke(const SetQuoteIntent()),
      ),
      const PlatformMenuItemGroup(members: []),
      PlatformMenuItem(
        label: checkedLabel('Bold', f.bold),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyB, meta: true),
        onSelected: () => _invoke(const ToggleBoldIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Italic', f.italic),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
        onSelected: () => _invoke(const ToggleItalicIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Underline', f.underline),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyU, meta: true),
        onSelected: () => _invoke(const ToggleUnderlineIntent()),
      ),
      PlatformMenuItem(
        label: checkedLabel('Strikethrough', f.strikethrough),
        shortcut: const SingleActivator(LogicalKeyboardKey.keyX, alt: true, meta: true),
        onSelected: () => _invoke(const ToggleStrikethroughIntent()),
      ),
    ];
