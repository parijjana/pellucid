import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/search/providers/search_provider.dart';

void main() {
  group('SearchProvider replace additions (Phase 1)', () {
    test('replaceMode defaults to false and replaceQuery defaults to empty', () {
      final provider = SearchProvider();
      expect(provider.replaceMode, isFalse);
      expect(provider.replaceQuery, isEmpty);
    });

    test('toggleReplaceMode flips state and notifies listeners', () {
      final provider = SearchProvider();
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.toggleReplaceMode();
      expect(provider.replaceMode, isTrue);
      expect(notifyCount, 1);

      provider.toggleReplaceMode();
      expect(provider.replaceMode, isFalse);
      expect(notifyCount, 2);
    });

    test('toggleReplaceMode(isOpen:) sets an explicit state and no-ops if unchanged', () {
      final provider = SearchProvider();
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.toggleReplaceMode(isOpen: true);
      expect(provider.replaceMode, isTrue);
      expect(notifyCount, 1);

      // Already true: no-op, no extra notification.
      provider.toggleReplaceMode(isOpen: true);
      expect(notifyCount, 1);
    });

    test('setReplaceQuery updates replaceQuery and no-ops on unchanged value', () {
      final provider = SearchProvider();
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setReplaceQuery('dog');
      expect(provider.replaceQuery, 'dog');
      expect(notifyCount, 1);

      provider.setReplaceQuery('dog');
      expect(notifyCount, 1);
    });

    test('closing search resets replaceMode and replaceQuery', () {
      final provider = SearchProvider();
      provider.toggleSearch(isOpen: true);
      provider.setQuery('cat');
      provider.toggleReplaceMode(isOpen: true);
      provider.setReplaceQuery('dog');

      provider.toggleSearch(isOpen: false);

      expect(provider.replaceMode, isFalse);
      expect(provider.replaceQuery, isEmpty);
      expect(provider.query, isEmpty);
    });

    test('updateMatchOffsets recomputes offsets and index after a replace shrinks matches', () {
      final provider = SearchProvider();
      provider.setQuery('cat');
      provider.updateMatchOffsets('cat sat cat mat cat');
      expect(provider.matchOffsets, [0, 8, 16]);
      expect(provider.currentMatchIndex, 0);

      // Simulate a Replace-one at offset 0 turning "cat" into "dog" (no longer
      // matching "cat"): the remaining two matches shift left by one char.
      const replaced = 'dog sat cat mat cat';
      provider.updateMatchOffsets(replaced);

      expect(provider.matchOffsets, [8, 16]);
      // currentMatchIndex (0) stays in bounds, so it now points at what was
      // previously the *next* match -- Replace advances forward automatically.
      expect(provider.currentMatchIndex, 0);
    });

    test('updateMatchOffsets after Replace All collapses to zero matches', () {
      final provider = SearchProvider();
      provider.setQuery('cat');
      provider.updateMatchOffsets('cat sat cat mat cat');
      expect(provider.matchOffsets.length, 3);

      provider.updateMatchOffsets('dog sat dog mat dog');
      expect(provider.matchOffsets, isEmpty);
      expect(provider.currentMatchIndex, -1);
    });
  });
}
