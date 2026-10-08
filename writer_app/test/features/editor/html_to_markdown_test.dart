import 'package:flutter_test/flutter_test.dart';
import 'package:pellucid/features/editor/html_to_markdown.dart';

void main() {
  String md(String html) => htmlToMarkdown(html) ?? '';

  group('inline formatting', () {
    test('bold, italic, strikethrough, links', () {
      expect(
        md(
          '<p>a <b>bold</b> <i>it</i> <s>gone</s> <a href="https://x.org/p?a=1">link</a></p>',
        ),
        'a **bold** *it* ~~gone~~ [link](https://x.org/p?a=1)',
      );
    });

    test('strong/em nesting becomes ***', () {
      expect(
        md(
          '<p><strong><em>both</em></strong> and <em><strong>both</strong></em></p>',
        ),
        '***both*** and ***both***',
      );
    });

    test('edge spaces stay outside the markers and neighbours merge', () {
      expect(md('<p><b>one </b><b>two</b> end</p>'), '**one two** end');
      expect(md('<p>x<b> padded </b>y</p>'), 'x **padded** y');
    });

    test('unsafe link schemes are dropped, text kept', () {
      expect(
        md(
          '<p><a href="javascript:alert(1)">click</a> <a href="/rel">rel</a></p>',
        ),
        'click rel',
      );
    });

    test('colours, fonts and sizes are dropped', () {
      expect(
        md(
          '<p><span style="color:#f00;font-family:Arial;font-size:20pt">plain</span> <font color="red" size="5">text</font></p>',
        ),
        'plain text',
      );
    });

    test('underline: <u>, Word-style <u> and span style become <u>', () {
      expect(md('<p>a <u>under</u> b</p>'), 'a <u>under</u> b');
      expect(md('<p><b><u>both</u></b></p>'), '**<u>both</u>**');
      expect(md("<p><span style='text-decoration:underline;text-underline:single'>word</span> x</p>"), '<u>word</u> x');
      expect(md('<p><span style="text-decoration-line: underline">w</span></p>'), '<u>w</u>');
    });

    test('a link keeps no <u> from its default underline', () {
      expect(md('<p><a href="https://x.org"><u>link</u></a> <a href="https://x.org" style="text-decoration:underline"><span style="text-decoration:underline">l2</span></a></p>'),
          '[link](https://x.org) [l2](https://x.org)');
    });

    test('whitespace collapses; nbsp becomes a space', () {
      expect(md('<p>a\n   b&nbsp;&nbsp;c</p>'), 'a b c');
    });
  });

  group('blocks', () {
    test(
      'headings H1-H3, deeper levels clamp to H3, inline bold in a heading is dropped',
      () {
        expect(
          md('<h1>One</h1><h2><b>Two</b></h2><h3>Three</h3><h5>Five</h5>'),
          '# One\n## Two\n### Three\n### Five',
        );
      },
    );

    test('paragraphs, line breaks and an empty paragraph', () {
      expect(
        md('<p>first</p><p>second<br>third</p><p><br></p><p>last</p>'),
        'first\nsecond\nthird\n\nlast',
      );
    });

    test('block quote, nested paragraphs', () {
      expect(
        md(
          '<blockquote><p>Quoted <b>text</b></p><p>more</p></blockquote><p>after</p>',
        ),
        '> Quoted **text**\n> more\nafter',
      );
    });

    test('bullet, numbered and nested lists', () {
      expect(
        md(
          '<ul><li>a<ul><li>a1</li><li>a2<ol><li>deep</li></ol></li></ul></li><li>b</li></ul>'
          '<ol start="3"><li>three</li><li>four</li></ol>',
        ),
        '- a\n    - a1\n    - a2\n        1. deep\n- b\n3. three\n4. four',
      );
    });

    test('list item wrapping a paragraph', () {
      expect(
        md('<ul><li><p>one <b>b</b></p></li><li><p>two</p></li></ul>'),
        '- one **b**\n- two',
      );
    });

    test('checklists: input checkboxes and ballot characters', () {
      expect(
        md(
          '<ul><li><input type="checkbox" checked> done</li><li><input type="checkbox"> todo</li><li>☑ ballot</li></ul>',
        ),
        '- [x] done\n- [ ] todo\n- [x] ballot',
      );
    });

    test('tables become tab-separated plain rows', () {
      expect(
        md(
          '<table><tr><th>Name</th><th>Qty</th></tr><tr><td>Tea</td><td><b>2</b></td></tr></table>',
        ),
        'Name\tQty\nTea\t**2**',
      );
    });

    test('scripts, styles, images and head are ignored', () {
      expect(
        md(
          '<html><head><title>T</title><style>p{color:red}</style></head><body><script>x()</script><p>Hi<img src="a.png"></p></body></html>',
        ),
        'Hi',
      );
    });

    test('empty / whitespace-only html gives null', () {
      expect(htmlToMarkdown('<p> </p><div></div>'), isNull);
    });

    test('pre-formatted text keeps its spacing', () {
      expect(
        md('<div style="white-space: pre;">  indented<br>line two</div>'),
        '  indented\nline two',
      );
    });
  });

  group('fixtures', () {
    test(
      'Word-style HTML: mso list paragraphs, title, conditional comments, o:p',
      () {
        const word = '''
<html xmlns:o="urn:schemas-microsoft-com:office:office"><head><meta name=Generator content="Microsoft Word 15">
<style><!-- p.MsoNormal {margin:0cm; font-size:11.0pt; font-family:"Calibri"} --></style></head>
<body lang=EN-GB><!--StartFragment-->
<p class=MsoTitle><span lang=EN-US>The Title</span><o:p></o:p></p>
<h1><span style='font-size:20pt;color:#2F5496'>Chapter one</span></h1>
<p class=MsoNormal><span style='font-family:"Calibri"'>Some <b style='mso-bidi-font-weight:normal'>bold</b> and <i>italic</i> text.</span><o:p></o:p></p>
<p class=MsoListParagraphCxSpFirst style='text-indent:-18.0pt;mso-list:l0 level1 lfo1'><![if !supportLists]><span style='font-family:Symbol;mso-list:Ignore'>·<span style='font:7.0pt "Times New Roman"'>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; </span></span><![endif]>First bullet<o:p></o:p></p>
<p class=MsoListParagraphCxSpMiddle style='margin-left:72.0pt;mso-list:l0 level2 lfo1'><![if !supportLists]><span style='mso-list:Ignore'>o<span>&nbsp;&nbsp;</span></span><![endif]>Nested <b>bullet</b><o:p></o:p></p>
<p class=MsoListParagraphCxSpLast style='mso-list:l0 level1 lfo1'><![if !supportLists]><span style='mso-list:Ignore'>·<span>&nbsp;</span></span><![endif]>Second bullet<o:p></o:p></p>
<p class=MsoListParagraphCxSpFirst style='mso-list:l1 level1 lfo2'><![if !supportLists]><span style='mso-list:Ignore'>1.<span>&nbsp;&nbsp;</span></span><![endif]>One<o:p></o:p></p>
<p class=MsoListParagraphCxSpLast style='mso-list:l1 level1 lfo2'><![if !supportLists]><span style='mso-list:Ignore'>2.<span>&nbsp;&nbsp;</span></span><![endif]>Two<o:p></o:p></p>
<table class=MsoTableGrid><tr><td><p class=MsoNormal>A</p></td><td><p class=MsoNormal>B</p></td></tr></table>
<!--EndFragment--></body></html>''';
        expect(md(word), '''
# The Title
# Chapter one
Some **bold** and *italic* text.
- First bullet
    - Nested **bullet**
- Second bullet
1. One
2. Two
A\tB''');
      },
    );

    test(
      'Google Docs: bold wrapper with weight normal, span styles, headings, links',
      () {
        const docs = '''
<meta charset='utf-8'><meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1234-abcd">
<h1 dir="ltr" style="line-height:1.38;margin-top:20pt;"><span style="font-size:20pt;font-family:Arial,sans-serif;color:#000000;font-weight:400;">Heading</span></h1>
<p dir="ltr" style="line-height:1.38;"><span style="font-size:11pt;font-family:Arial;font-weight:700;">Bold</span><span style="font-size:11pt;font-weight:400;"> then </span><span style="font-style:italic;font-weight:400;">italic</span><span style="font-weight:400;"> and </span><span style="text-decoration:line-through;">struck</span><span> with a </span><a href="https://www.google.com/url?q=https://example.com" style="text-decoration:none;"><span style="color:#1155cc;text-decoration:underline;">link</span></a></p>
<ul style="margin-top:0;"><li dir="ltr" style="list-style-type:disc;" aria-level="1"><p dir="ltr" role="presentation"><span style="font-weight:400;">item one</span></p></li>
<ul style="margin-top:0;"><li dir="ltr" style="list-style-type:circle;" aria-level="2"><p dir="ltr" role="presentation"><span style="font-weight:400;">nested</span></p></li></ul>
<li dir="ltr" aria-level="1"><p dir="ltr"><span>item two</span></p></li></ul>
</b>''';
        expect(md(docs), '''
# Heading
**Bold** then *italic* and ~~struck~~ with a [link](https://www.google.com/url?q=https://example.com)
- item one
    - nested
- item two''');
      },
    );

    test(
      'web page: nav, article, nested inline junk, quote with cite, stray styles',
      () {
        const page = '''
<html><body><nav><a href="/">Home</a></nav><article class="post">
<h2 class="title" style="font-family:Georgia">A <em>fine</em> day</h2>
<div class="byline"><span style="color:gray">by</span> <strong>Someone</strong></div>
<p>Text with <span class="x"><b><i>nested <u>junk</u></i></b></span>, a <code>snippet</code> and <a href="mailto:a@b.co">mail</a>.</p>
<blockquote cite="x"><p>Wise words.</p></blockquote>
<ol><li>Step <b>one</b></li><li>Step two<ul><li>detail</li></ul></li></ol>
<hr><p style="font-size:8px">Footer &amp; &lt;small&gt; &copy; 2026</p></article></body></html>''';
        expect(md(page), '''
Home
## A *fine* day
by **Someone**
Text with ***nested <u>junk</u>***, a `snippet` and [mail](mailto:a@b.co).
> Wise words.
1. Step **one**
2. Step two
    - detail
Footer & <small> © 2026''');
      },
    );

    test(
      'email-style: quoted reply, signature, divs and tables for layout',
      () {
        const mail = '''
<html><body><div dir="ltr"><div>Hi team,</div><div><br></div><div>Please see <b>below</b>:</div>
<div><span style="color:rgb(34,34,34)">1) first</span></div>
<blockquote class="gmail_quote" style="margin:0 0 0 .8ex;border-left:1px #ccc solid"><div dir="ltr">On Mon, Bob wrote:<br><div>Original <i>message</i></div></div></blockquote>
<div><br></div><div>-- <br><div dir="ltr" class="gmail_signature"><div>Alice<br>Writer</div></div></div></div></body></html>''';
        expect(md(mail), '''
Hi team,

Please see **below**:
1) first
> On Mon, Bob wrote:
> Original *message*

--
Alice
Writer''');
      },
    );
  });

  group('htmlAddsStructure', () {
    test('markers present: worth using', () {
      expect(htmlAddsStructure('**a** b', 'a b'), isTrue);
    });
    test('same words as the plain text: keep the plain paste', () {
      expect(htmlAddsStructure('a b\nc', 'a b\nc'), isFalse);
      expect(htmlAddsStructure('a b', null), isTrue);
    });
  });
}
