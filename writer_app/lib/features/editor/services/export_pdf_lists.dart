// Description: Markdown -> PDF widgets with real lists (backlog items 21, 3, 17).
//
// htmltopdfwidgets flattens nested lists into one paragraph and drops the
// numbers of nested ones, so list blocks are drawn here and everything else
// still goes through it. Levels match the editor: bullets • ◦ ▪ (filled disc,
// ring, square), numbers 1. a. i., checkboxes as drawn boxes (the standard PDF
// fonts have no ☐, and nothing is embedded: see the font rule in CLAUDE.md).

import 'package:htmltopdfwidgets/htmltopdfwidgets.dart' as htp;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../list_marker.dart';
import 'export_markdown.dart';

/// [markdown] as PDF widgets, in order. Each list item is its own widget so a
/// long list can break across pages.
Future<List<pw.Widget>> markdownToPdfWidgets(String markdown) async {
  final doc = md.Document(extensionSet: exportExtensionSet);
  final nodes = doc.parseLines(markdown.replaceAll('\r\n', '\n').split('\n'));
  final out = <pw.Widget>[];
  final pending = <md.Node>[];

  Future<void> flush() async {
    if (pending.isEmpty) return;
    out.addAll(await htp.HTMLToPdf().convert(md.renderToHtml(List.of(pending))));
    pending.clear();
  }

  for (final node in nodes) {
    if (node is md.Element && (node.tag == 'ul' || node.tag == 'ol')) {
      await flush();
      await _list(node, 0, out);
    } else {
      pending.add(node);
    }
  }
  await flush();
  return out;
}

bool _isList(md.Node n) => n is md.Element && (n.tag == 'ul' || n.tag == 'ol');

Future<void> _list(md.Element list, int level, List<pw.Widget> out) async {
  final bool ordered = list.tag == 'ol';
  int number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
  for (final item in (list.children ?? const <md.Node>[]).whereType<md.Element>()) {
    if (item.tag != 'li') continue;
    final rest = <md.Node>[];
    final nested = <md.Element>[];
    for (final c in item.children ?? const <md.Node>[]) {
      if (_isList(c)) {
        nested.add(c as md.Element);
      } else {
        rest.add(c);
      }
    }
    final task = _takeTaskBox(rest);
    final content = await _content(rest);
    final pw.Widget marker;
    double markerWidth = 20;
    if (task != null) {
      marker = _checkbox(task.done);
    } else if (ordered) {
      final label = '${numberLabelForLevel(number, level)}.';
      markerWidth = label.length > 3 ? 28 : 22;
      marker = pw.Padding(padding: const pw.EdgeInsets.only(right: 5), child: pw.Text(label, textAlign: pw.TextAlign.right));
    } else {
      marker = _bullet(level);
    }
    if (ordered) number++;
    out.add(pw.Padding(
      padding: pw.EdgeInsets.only(left: 18.0 * level, bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: markerWidth, child: marker),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: content)),
        ],
      ),
    ));
    for (final n in nested) {
      await _list(n, level + 1, out);
    }
  }
}

Future<List<pw.Widget>> _content(List<md.Node> nodes) async {
  if (nodes.isEmpty) return const [];
  final blocky = nodes.any((n) => n is md.Element && (n.tag == 'p' || n.tag.startsWith('h') || n.tag == 'blockquote'));
  final html = md.renderToHtml(nodes);
  return htp.HTMLToPdf().convert(blocky ? html : '<p>$html</p>');
}

class _Task {
  final bool done;
  const _Task(this.done);
}

/// Removes a leading checkbox from an item's content and says whether it is ticked.
_Task? _takeTaskBox(List<md.Node> nodes) {
  if (nodes.isEmpty) return null;
  _Task? check(md.Node n) {
    if (n is md.Element && n.tag == 'span' && (n.attributes['class'] ?? '').startsWith('task-box')) {
      return _Task((n.attributes['class'] ?? '').contains('done'));
    }
    return null;
  }

  final first = nodes.first;
  final direct = check(first);
  if (direct != null) {
    nodes.removeAt(0);
    // The single space after the box.
    if (nodes.isNotEmpty && nodes.first is md.Text) {
      final t = (nodes.first as md.Text).text;
      if (t.trim().isEmpty) {
        nodes.removeAt(0);
      }
    }
    return direct;
  }
  if (first is md.Element && first.tag == 'p' && (first.children?.isNotEmpty ?? false)) {
    final inner = check(first.children!.first);
    if (inner != null) {
      final kids = List<md.Node>.of(first.children!)..removeAt(0);
      if (kids.isNotEmpty && kids.first is md.Text && (kids.first as md.Text).text.trim().isEmpty) kids.removeAt(0);
      nodes[0] = md.Element('p', kids);
      return inner;
    }
  }
  return null;
}

pw.Widget _bullet(int level) {
  final kind = level % 3;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 5.5, left: 5),
    child: pw.Container(
      width: 4.5,
      height: 4.5,
      decoration: pw.BoxDecoration(
        shape: kind == 2 ? pw.BoxShape.rectangle : pw.BoxShape.circle,
        color: kind == 1 ? null : PdfColors.black,
        border: kind == 1 ? pw.Border.all(width: 0.7) : null,
      ),
    ),
  );
}

pw.Widget _checkbox(bool done) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2.5, left: 2),
    child: pw.Container(
      width: 9,
      height: 9,
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
      child: done ? pw.Center(child: pw.Text('x', style: const pw.TextStyle(fontSize: 7))) : null,
    ),
  );
}
