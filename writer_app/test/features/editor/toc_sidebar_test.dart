// Description: Widget tests for the TOC navigation sidebar, verifying that
// per-chapter word counts render when enabled and are hidden when disabled.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:pellucid/features/editor/providers/editor_provider.dart';
import 'package:pellucid/features/editor/providers/theme_provider.dart';
import 'package:pellucid/features/editor/utils/toc_parser.dart';
import 'package:pellucid/features/editor/widgets/editor_navigation_sidebar.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';

class MockEditorProvider extends Mock implements EditorProvider {}

void main() {
  late MockEditorProvider mockEditor;
  late SearchProvider searchProvider;

  const headers = <TocHeader>[
    (title: 'Chapter One', line: 0, level: 1, wordCount: 42),
    (title: 'Section A', line: 3, level: 2, wordCount: 17),
  ];

  setUp(() {
    mockEditor = MockEditorProvider();
    searchProvider = SearchProvider();
    when(() => mockEditor.content).thenReturn('# Chapter One\n...');
    when(() => mockEditor.documentLoadFailed).thenReturn(false);
  });

  Widget buildSidebar({required bool showWordCounts}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EditorProvider>.value(value: mockEditor),
        ChangeNotifierProvider<SearchProvider>.value(value: searchProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 250,
            child: EditorNavigationSidebar(
              theme: WriterTheme.presets[0],
              headers: headers,
              onHeaderTap: (_) {},
              showWordCounts: showWordCounts,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders per-chapter word counts when enabled', (tester) async {
    await tester.pumpWidget(buildSidebar(showWordCounts: true));

    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('hides word counts when disabled', (tester) async {
    await tester.pumpWidget(buildSidebar(showWordCounts: false));

    // Titles still show, counts do not.
    expect(find.text('Chapter One'), findsOneWidget);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.text('42'), findsNothing);
    expect(find.text('17'), findsNothing);
  });
}
