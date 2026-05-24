import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/settings/providers/settings_provider.dart';
import 'package:pellucid/features/editor/widgets/alarm_setter_dialog.dart';
import 'package:provider/provider.dart';

class MockThemeProvider extends Mock implements ThemeProvider {}
class MockSettingsProvider extends Mock implements SettingsProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockThemeProvider mockTheme;
  late MockSettingsProvider mockSettings;

  setUp(() {
    mockTheme = MockThemeProvider();
    mockSettings = MockSettingsProvider();

    when(() => mockTheme.currentTheme).thenReturn(WriterTheme.presets[0]);
    when(() => mockSettings.alarmTime).thenReturn(null);
    when(() => mockSettings.setAlarm(any())).thenAnswer((_) {});
    when(() => mockSettings.clearAlarm()).thenAnswer((_) {});
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: mockTheme),
        ChangeNotifierProvider<SettingsProvider>.value(value: mockSettings),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AlarmSetterDialog(),
        ),
      ),
    );
  }

  testWidgets('AlarmSetterDialog displays inputs and has initial focus on Hours', (WidgetTester tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(find.text('SET ALARM'), findsOneWidget);

    // Verify time inputs exist (labeled HOURS and MINUTES)
    expect(find.text('HOURS'), findsOneWidget);
    expect(find.text('MINUTES'), findsOneWidget);

    // Initial value in Hours should be some default (now + 1 hour)
    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    final hourField = tester.widget<TextField>(textFields.first);
    expect(hourField.focusNode!.hasFocus, isTrue, reason: 'Hours field should have focus initially');
  });

  testWidgets('Up/Down arrow keys adjust hour values', (WidgetTester tester) async {
    // Stub custom time to make initial hour predictable (e.g., 10:30)
    final initialTime = DateTime(2026, 5, 22, 10, 30);
    when(() => mockSettings.alarmTime).thenReturn(initialTime);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    final hourFieldFinder = textFields.first;

    // Verify initial value
    expect(tester.widget<TextField>(hourFieldFinder).controller!.text, '10');

    // Press Arrow Up to increment
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(hourFieldFinder).controller!.text, '11');

    // Press Arrow Down to decrement twice
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(hourFieldFinder).controller!.text, '09');
  });

  testWidgets('Typing 2 digits in Hours auto-focuses Minutes', (WidgetTester tester) async {
    // Stub custom time to make initial hour predictable (e.g., 10:30)
    final initialTime = DateTime(2026, 5, 22, 10, 30);
    when(() => mockSettings.alarmTime).thenReturn(initialTime);

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    final hourField = tester.widget<TextField>(textFields.first);
    final minuteField = tester.widget<TextField>(textFields.last);

    expect(hourField.focusNode!.hasFocus, isTrue);
    expect(minuteField.focusNode!.hasFocus, isFalse);

    // Enter 2 digits into Hour field
    await tester.enterText(textFields.first, '23');
    await tester.pumpAndSettle();

    expect(hourField.focusNode!.hasFocus, isFalse, reason: 'Hour field should lose focus');
    expect(minuteField.focusNode!.hasFocus, isTrue, reason: 'Minute field should gain focus');
  });

  testWidgets('Left/Right arrow keys navigate focus between inputs and buttons', (WidgetTester tester) async {
    // To have the CLEAR button visible, let's stub alarmTime as non-null
    when(() => mockSettings.alarmTime).thenReturn(DateTime(2026, 5, 22, 10, 30));

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    final hourFocus = tester.widget<TextField>(textFields.first).focusNode!;
    final minuteFocus = tester.widget<TextField>(textFields.last).focusNode!;

    expect(hourFocus.hasFocus, isTrue);

    // Right Arrow -> Minute Focus
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(minuteFocus.hasFocus, isTrue);

    // Right Arrow -> CLEAR button Focus
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    
    // Find focus of CLEAR
    final clearFinder = find.text('CLEAR');

    expect(clearFinder, findsOneWidget);
    
    // Left Arrow -> back to Minute Focus
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(minuteFocus.hasFocus, isTrue);

    // Left Arrow -> back to Hour Focus
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(hourFocus.hasFocus, isTrue);
  });

  testWidgets('Enter key invokes save alarm', (WidgetTester tester) async {
    registerFallbackValue(DateTime.now());

    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    // Enter valid hour '08' and valid minute '45'
    await tester.enterText(textFields.first, '08');
    await tester.pumpAndSettle();
    await tester.enterText(textFields.last, '45');
    await tester.pumpAndSettle();

    // Verify hour/minute values
    expect(tester.widget<TextField>(textFields.first).controller!.text, '08');
    expect(tester.widget<TextField>(textFields.last).controller!.text, '45');

    // Press Enter to save
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Verify setAlarm was called
    verify(() => mockSettings.setAlarm(any())).called(1);
  });
}
