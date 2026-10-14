// Description: Owner pre-check 1.1.0 - the spell-check on/off notice is faint
// and fades away on its own (owner check "Cmd+Opt+K ... notice is faint and fades").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/widgets/status_notice.dart';

void main() {
  testWidgets('notice text is the page foreground at 60% alpha, then fades out and is removed', (tester) async {
    final theme = WriterTheme.presets.first;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold(body: SizedBox())));
    showStatusNotice(key.currentState!.overlay!, theme, 'Spell check off');
    await tester.pump();

    final text = tester.widget<Text>(find.text('Spell check off'));
    expect(text.style!.color!.a, closeTo(theme.foregroundColor.a * 0.6, 0.01));
    expect(text.style!.fontSize, 12);

    double opacity() => tester.widget<FadeTransition>(find.byType(FadeTransition).last).opacity.value;
    expect(opacity(), closeTo(1, 0.01));
    await tester.pump(const Duration(milliseconds: 1000));
    final mid = opacity();
    expect(mid, lessThan(1));
    expect(mid, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(find.text('Spell check off'), findsNothing);
  });

  testWidgets('a newer notice replaces one that is still fading', (tester) async {
    final theme = WriterTheme.presets.first;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold(body: SizedBox())));
    showStatusNotice(key.currentState!.overlay!, theme, 'Spell check off');
    await tester.pump(const Duration(milliseconds: 500));
    showStatusNotice(key.currentState!.overlay!, theme, 'Spell check on');
    await tester.pump();
    expect(find.text('Spell check off'), findsNothing);
    expect(find.text('Spell check on'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
