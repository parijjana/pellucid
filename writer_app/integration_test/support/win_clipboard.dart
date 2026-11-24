// Raw Windows clipboard access through dart:ffi, for tests that must look at the bytes the app's native
// channel wrote (or put bytes there that Word or a browser would). Windows only.

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int cfUnicodeText = 13;
const int _gmemMoveable = 0x0002;

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(int) _openClipboard =
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');
final int Function() _closeClipboard = _user32.lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
final int Function() _emptyClipboard = _user32.lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');
final int Function(int) _enumFormats =
    _user32.lookupFunction<Uint32 Function(Uint32), int Function(int)>('EnumClipboardFormats');
final int Function(int, Pointer<Utf16>, int) _formatName = _user32
    .lookupFunction<Int32 Function(Uint32, Pointer<Utf16>, Int32), int Function(int, Pointer<Utf16>, int)>(
        'GetClipboardFormatNameW');
final int Function(Pointer<Utf16>) _registerFormat =
    _user32.lookupFunction<Uint32 Function(Pointer<Utf16>), int Function(Pointer<Utf16>)>('RegisterClipboardFormatW');
final Pointer<Void> Function(int) _getData =
    _user32.lookupFunction<Pointer<Void> Function(Uint32), Pointer<Void> Function(int)>('GetClipboardData');
final Pointer<Void> Function(int, Pointer<Void>) _setData = _user32.lookupFunction<
    Pointer<Void> Function(Uint32, Pointer<Void>), Pointer<Void> Function(int, Pointer<Void>)>('SetClipboardData');
final Pointer<Void> Function(int, int) _globalAlloc =
    _kernel32.lookupFunction<Pointer<Void> Function(Uint32, IntPtr), Pointer<Void> Function(int, int)>('GlobalAlloc');
final Pointer<Uint8> Function(Pointer<Void>) _globalLock = _kernel32
    .lookupFunction<Pointer<Uint8> Function(Pointer<Void>), Pointer<Uint8> Function(Pointer<Void>)>('GlobalLock');
final int Function(Pointer<Void>) _globalUnlock =
    _kernel32.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('GlobalUnlock');
final int Function(Pointer<Void>) _globalSize =
    _kernel32.lookupFunction<IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>('GlobalSize');

int registerFormat(String name) {
  final p = name.toNativeUtf16();
  try {
    return _registerFormat(p);
  } finally {
    calloc.free(p);
  }
}

/// Runs [body] with the clipboard open (retries while another process holds it).
T withClipboard<T>(T Function() body) {
  bool opened = false;
  for (int i = 0; i < 50 && !opened; i++) {
    opened = _openClipboard(0) != 0;
    if (!opened) {
      final end = DateTime.now().add(const Duration(milliseconds: 40));
      while (DateTime.now().isBefore(end)) {}
    }
  }
  if (!opened) throw StateError('OpenClipboard failed');
  try {
    return body();
  } finally {
    _closeClipboard();
  }
}

/// Registered/standard format ids and names currently on the clipboard.
Map<int, String> listFormats() => withClipboard(() {
      final out = <int, String>{};
      final buf = calloc<Uint16>(256).cast<Utf16>();
      try {
        for (int f = _enumFormats(0); f != 0; f = _enumFormats(f)) {
          final n = _formatName(f, buf, 256);
          out[f] = n > 0 ? buf.toDartString(length: n) : 'standard($f)';
        }
      } finally {
        calloc.free(buf);
      }
      return out;
    });

/// The full block for [format] (GlobalSize bytes), or null when absent.
Uint8List? readFormat(int format) => withClipboard(() {
      final h = _getData(format);
      if (h == nullptr) return null;
      final size = _globalSize(h);
      final p = _globalLock(h);
      if (p == nullptr) return null;
      try {
        return Uint8List.fromList(p.asTypedList(size));
      } finally {
        _globalUnlock(h);
      }
    });

/// Bytes up to the first NUL.
Uint8List untilNul(Uint8List b) {
  final i = b.indexOf(0);
  return i < 0 ? b : Uint8List.sublistView(b, 0, i);
}

String? readUnicodeText() {
  final b = readFormat(cfUnicodeText);
  if (b == null) return null;
  final u16 = Uint16List.view(b.buffer, b.offsetInBytes, b.lengthInBytes ~/ 2);
  int n = u16.indexOf(0);
  if (n < 0) n = u16.length;
  return String.fromCharCodes(u16, 0, n);
}

/// Replaces the clipboard with the given formats (format id -> bytes, NUL appended by the caller if wanted).
void setFormats(Map<int, Uint8List> formats) => withClipboard(() {
      _emptyClipboard();
      formats.forEach((fmt, bytes) {
        final h = _globalAlloc(_gmemMoveable, bytes.length);
        final p = _globalLock(h);
        p.asTypedList(bytes.length).setAll(0, bytes);
        _globalUnlock(h);
        if (_setData(fmt, h) == nullptr) throw StateError('SetClipboardData($fmt) failed');
      });
    });

void clearClipboard() => withClipboard(() => _emptyClipboard());

Uint8List utf16Bytes(String s) {
  final u = Uint16List(s.length + 1);
  for (int i = 0; i < s.length; i++) {
    u[i] = s.codeUnitAt(i);
  }
  return u.buffer.asUint8List();
}

Uint8List utf8Nul(String s) => Uint8List.fromList([...utf8.encode(s), 0]);

/// Plain-text snapshot, restored by [restoreText]. Text only: other formats are not preserved.
String? saveClipboardText() => readUnicodeText();

void restoreText(String? text) {
  if (text == null) {
    clearClipboard();
  } else {
    setFormats({cfUnicodeText: utf16Bytes(text)});
  }
}

class CfHtml {
  final int startHtml, endHtml, startFragment, endFragment;
  final String header;
  final String fragment;
  final List<String> problems;
  CfHtml(this.startHtml, this.endHtml, this.startFragment, this.endFragment, this.header, this.fragment, this.problems);
}

/// Parses and validates a CF_HTML block against its own bytes (offsets are byte offsets).
CfHtml parseCfHtml(Uint8List block) {
  final data = untilNul(block);
  final text = latin1.decode(data); // header is ASCII; offsets are byte offsets
  final problems = <String>[];
  int read(String key) {
    final m = RegExp('$key:(\\d+)').firstMatch(text.substring(0, text.length < 400 ? text.length : 400));
    if (m == null) {
      problems.add('missing $key');
      return -1;
    }
    return int.parse(m.group(1)!);
  }

  final sh = read('StartHTML'), eh = read('EndHTML'), sf = read('StartFragment'), ef = read('EndFragment');
  final headerEnd = text.indexOf('<');
  if (sh != headerEnd) problems.add('StartHTML=$sh but first "<" is at byte $headerEnd');
  if (eh != data.length) problems.add('EndHTML=$eh but data is ${data.length} bytes');
  if (!(sh <= sf && sf <= ef && ef <= eh)) problems.add('offsets not ordered: $sh $sf $ef $eh');
  var fragment = '';
  if (sf >= 0 && ef >= sf && ef <= data.length) {
    fragment = utf8.decode(data.sublist(sf, ef), allowMalformed: false);
    final before = latin1.decode(data.sublist((sf - 20).clamp(0, data.length), sf));
    final after = latin1.decode(data.sublist(ef, (ef + 18).clamp(0, data.length)));
    if (!before.endsWith('<!--StartFragment-->')) problems.add('bytes before StartFragment: "$before"');
    if (!after.startsWith('<!--EndFragment-->')) problems.add('bytes at EndFragment: "$after"');
  } else {
    problems.add('fragment offsets out of range');
  }
  return CfHtml(sh, eh, sf, ef, text.substring(0, headerEnd < 0 ? 0 : headerEnd), fragment, problems);
}

/// Builds a CF_HTML block the way Word/browsers do: [prefix] + fragment + [suffix], header with 10-digit offsets.
Uint8List buildCfHtml(String prefix, String fragment, String suffix, {String extraHeader = ''}) {
  String hdr(int sh, int eh, int sf, int ef) =>
      'Version:0.9\r\nStartHTML:${sh.toString().padLeft(10, '0')}\r\nEndHTML:${eh.toString().padLeft(10, '0')}\r\n'
      'StartFragment:${sf.toString().padLeft(10, '0')}\r\nEndFragment:${ef.toString().padLeft(10, '0')}\r\n$extraHeader';
  final hl = utf8.encode(hdr(0, 0, 0, 0)).length;
  final pre = utf8.encode(prefix).length, frag = utf8.encode(fragment).length, suf = utf8.encode(suffix).length;
  final h = hdr(hl, hl + pre + frag + suf, hl + pre, hl + pre + frag);
  return utf8Nul('$h$prefix$fragment$suffix');
}
