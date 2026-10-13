import Cocoa
import FlutterMacOS
import IOKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.overengineeredhobbies.pellucid/hardware",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      if call.method == "getMacHardwareInfo" {
        var info: [String: Any] = [:]
        
        // 1. Get model identifier
        let model = self.getDeviceModel()
        info["model"] = model
        
        // 2. Get housing-color
        if let housingColorHex = self.getHousingColor() {
          info["housingColor"] = housingColorHex
        }
        
        result(info)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let spellChannel = FlutterMethodChannel(
      name: "com.overengineeredhobbies.pellucid/spellcheck",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    spellChannel.setMethodCallHandler { (call, result) in
      if call.method == "checkSpelling" {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String else {
          result([])
          return
        }
        let language = args["language"] as? String ?? "en"
        let withSuggestions = args["withSuggestions"] as? Bool ?? true

        // A whole manuscript has hundreds of flagged words and guesses(...) costs
        // ~15 ms each, so the old loop froze the UI thread for many seconds.
        // requestChecking runs the scan off the main thread; suggestions are
        // fetched on demand ("suggest") unless the caller asks for them.
        if !withSuggestions {
          let length = (text as NSString).length
          NSSpellChecker.shared.requestChecking(
            of: text,
            range: NSRange(location: 0, length: length),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: nil,
            inSpellDocumentWithTag: 0
          ) { _, checked, _, _ in
            let items: [[String: Any]] = checked.map {
              ["start": $0.range.location, "end": $0.range.location + $0.range.length, "suggestions": [String]()]
            }
            DispatchQueue.main.async { result(items) }
          }
          return
        }

        let spellChecker = NSSpellChecker.shared
        var results: [[String: Any]] = []
        let nsStringText = text as NSString
        let textLength = nsStringText.length
        
        var searchOffset = 0
        while searchOffset < textLength {
          let misspelledRange = spellChecker.checkSpelling(
            of: text,
            startingAt: searchOffset,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
          )
          
          if misspelledRange.location == NSNotFound || misspelledRange.length == 0 || misspelledRange.location < searchOffset {
            break
          }
          
          let suggestions = spellChecker.guesses(forWordRange: misspelledRange, in: text, language: language, inSpellDocumentWithTag: 0) ?? []
          
          var resultItem: [String: Any] = [:]
          resultItem["start"] = misspelledRange.location
          resultItem["end"] = misspelledRange.location + misspelledRange.length
          resultItem["suggestions"] = suggestions
          results.append(resultItem)
          
          searchOffset = misspelledRange.location + misspelledRange.length
        }
        
        result(results)
      } else if call.method == "suggest" {
        guard let args = call.arguments as? [String: Any],
              let word = args["word"] as? String, !word.isEmpty,
              word.unicodeScalars.count <= 64 else {
          result([String]())
          return
        }
        let language = args["language"] as? String ?? "en"
        let ns = word as NSString
        let guesses = NSSpellChecker.shared.guesses(
          forWordRange: NSRange(location: 0, length: ns.length), in: word, language: language,
          inSpellDocumentWithTag: 0) ?? []
        result(guesses)
      } else if call.method == "learnWord" || call.method == "ignoreWord" {
        // One word only, as on the Dart side (isLearnableWord): 1-64 code
        // points, no whitespace or control characters. learnWord writes the
        // user's system-wide dictionary, so reject anything else here too.
        let rejected = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard let args = call.arguments as? [String: Any],
              let word = args["word"] as? String,
              !word.isEmpty,
              word.unicodeScalars.count <= 64,
              word.rangeOfCharacter(from: rejected) == nil else {
          result(false)
          return
        }
        if call.method == "learnWord" {
          NSSpellChecker.shared.learnWord(word)
        } else {
          NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: 0)
        }
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Copy from the editor: HTML + plain text for other apps, plus the
    // markdown under a private type so a paste inside Pellucid keeps it.
    let markdownType = NSPasteboard.PasteboardType("com.overengineeredhobbies.pellucid.markdown")
    let clipboardChannel = FlutterMethodChannel(
      name: "com.overengineeredhobbies.pellucid/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel.setMethodCallHandler { (call, result) in
      let pasteboard = NSPasteboard.general
      switch call.method {
      case "setRich":
        guard let args = call.arguments as? [String: Any],
              let plain = args["plain"] as? String,
              let html = args["html"] as? String,
              let markdown = args["markdown"] as? String else {
          result(FlutterError(code: "bad_args", message: "plain, html and markdown required", details: nil))
          return
        }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        // Richest type first: some apps (Pages) take the first type they
        // understand in pasteboard order, so plain text must come last.
        // Pages reads RTF, not public.html, for rich paste.
        if let rtf = pellucidRtfData(fromHtml: html) {
          item.setData(rtf, forType: .rtf)
        }
        item.setString("<meta charset=\"utf-8\">" + html, forType: .html)
        item.setString(markdown, forType: markdownType)
        item.setString(plain, forType: .string)
        pasteboard.writeObjects([item])
        result(nil)
      case "getMarkdown":
        result(pasteboard.string(forType: markdownType))
      case "getHtml":
        // Pasting formatted text (item 22): the HTML other apps put on the pasteboard.
        // Pages and TextEdit offer no HTML, only RTF/RTFD: convert that to simple HTML.
        if let html = pasteboard.string(forType: .html), !html.isEmpty {
          result(html)
        } else {
          result(pellucidHtmlFromPasteboard(pasteboard))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func getDeviceModel() -> String {
    let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    if service != 0 {
      defer { IOObjectRelease(service) }
      if let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
        if let modelString = String(data: modelData, encoding: .utf8) {
          return modelString.trimmingCharacters(in: .controlCharacters)
        }
      }
    }
    return ""
  }

  private func getHousingColor() -> String? {
    let entry = IORegistryEntryFromPath(kIOMasterPortDefault, "IODeviceTree:/")
    if entry != 0 {
      defer { IOObjectRelease(entry) }
      if let colorData = IORegistryEntryCreateCFProperty(entry, "housing-color" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
        return colorData.map { String(format: "%02hhx", $0) }.joined()
      }
    }
    return nil
  }
}


// BEGIN pellucidRtf
/// RTF for the copied HTML, so Pages/TextEdit keep formatting. The wrapper's
/// font style applies to this conversion only; the HTML on the pasteboard is
/// untouched. Returns nil on any failure (the other types are still written).
func pellucidRtfData(fromHtml html: String) -> Data? {
  let wrapped = "<html><head><meta charset=\"utf-8\"><style>"
    + "body { font-family: -apple-system, 'Helvetica Neue'; font-size: 12px; }"
    + "</style></head><body>" + html + "</body></html>"
  guard let data = wrapped.data(using: .utf8) else { return nil }
  guard let attributed = try? NSAttributedString(
    data: data,
    options: [
      .documentType: NSAttributedString.DocumentType.html,
      .characterEncoding: String.Encoding.utf8.rawValue,
    ],
    documentAttributes: nil
  ), attributed.length > 0 else { return nil }
  return attributed.rtf(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
  )
}
// END pellucidRtf

// BEGIN pellucidRtfToHtml
/// Pasted RTF/RTFD (Pages, TextEdit) to SIMPLE HTML for the Dart converter.
/// Structure only: paragraphs, bold/italic/underline/strike, links, lists.
/// Colours, fonts and sizes are dropped; no headings are guessed.
func pellucidHtmlFromAttributed(_ attr: NSAttributedString) -> String? {
  func esc(_ s: String) -> String {
    return s.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
  func isOrdered(_ l: NSTextList) -> Bool {
    let f = l.markerFormat.rawValue.lowercased()
    for k in ["disc", "circle", "square", "hyphen", "diamond", "check", "box"] where f.contains(k) { return false }
    return f.contains("decimal") || f.contains("roman") || f.contains("alpha") || f.contains("latin")
  }
  let ns = attr.string as NSString
  var out = ""
  var stack: [Bool] = []  // open lists, true = ordered
  var liOpen: [Bool] = []  // whether the <li> at each depth is still open
  func closeTo(_ depth: Int) {
    while stack.count > depth {
      if liOpen.removeLast() { out += "</li>" }
      out += stack.removeLast() ? "</ol>" : "</ul>"
    }
  }
  var loc = 0
  while loc < ns.length {
    let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
    loc = pr.location + pr.length
    var lineRange = pr
    while lineRange.length > 0 {
      let c = ns.character(at: lineRange.location + lineRange.length - 1)
      if c == 10 || c == 13 || c == 0x2028 || c == 0x2029 { lineRange.length -= 1 } else { break }
    }
    let style = attr.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
    let lists = style?.textLists ?? []
    // Drop the "\t•\t" / "\t1.\t" marker text Cocoa leaves at the start of list paragraphs.
    if let last = lists.last {
      let marker = last.marker(forItemNumber: 1)
      let first = ns.substring(with: lineRange)
      if first.hasPrefix("\t"), let r = first.range(of: "\t", range: first.index(after: first.startIndex)..<first.endIndex) {
        let mk = String(first[first.index(after: first.startIndex)..<r.lowerBound])
        let looksLikeMarker = mk == marker || mk.isEmpty || mk.count <= 8 && !mk.contains(" ")
        if looksLikeMarker {
          let dropUtf16 = first[first.startIndex..<r.upperBound].utf16.count
          lineRange = NSRange(location: lineRange.location + dropUtf16, length: lineRange.length - dropUtf16)
        }
      }
    }
    var inline = ""
    if lineRange.length > 0 {
      attr.enumerateAttributes(in: lineRange, options: []) { attrs, range, _ in
        let text = ns.substring(with: range)
          .replacingOccurrences(of: "\u{2028}", with: "\n")
          .replacingOccurrences(of: "\u{00A0}", with: " ")
          .replacingOccurrences(of: "\u{FFFC}", with: "")
        if text.isEmpty { return }
        var t = esc(text).replacingOccurrences(of: "\n", with: "<br>")
        var link: String? = nil
        if let u = attrs[.link] as? URL { link = u.absoluteString } else if let s = attrs[.link] as? String { link = s }
        if let font = attrs[.font] as? NSFont {
          let tr = font.fontDescriptor.symbolicTraits
          if tr.contains(.italic) { t = "<i>" + t + "</i>" }
          if tr.contains(.bold) { t = "<b>" + t + "</b>" }
        }
        if let n = attrs[.strikethroughStyle] as? Int, n != 0 { t = "<s>" + t + "</s>" }
        if link == nil, let n = attrs[.underlineStyle] as? Int, n != 0 { t = "<u>" + t + "</u>" }
        if let l = link { t = "<a href=\"" + esc(l) + "\">" + t + "</a>" }
        inline += t
      }
    }
    if !lists.isEmpty {
      let depth = lists.count
      closeTo(depth)
      // A different list kind at the same depth (bullets then numbers) is a new list.
      if stack.count == depth, stack[depth - 1] != isOrdered(lists[depth - 1]) { closeTo(depth - 1) }
      if stack.count == depth, liOpen[depth - 1] { out += "</li>"; liOpen[depth - 1] = false }
      while stack.count < depth {
        let ord = isOrdered(lists[stack.count])
        stack.append(ord)
        liOpen.append(false)
        out += ord ? "<ol>" : "<ul>"
      }
      out += "<li>" + inline
      liOpen[depth - 1] = true
    } else {
      closeTo(0)
      if inline.isEmpty { out += "<p><br></p>" } else { out += "<p>" + inline + "</p>" }
    }
  }
  closeTo(0)
  return out.isEmpty ? nil : out
}

/// RTF (preferred) or RTFD pasteboard content as simple HTML; nil if none.
func pellucidHtmlFromPasteboard(_ pb: NSPasteboard) -> String? {
  var attr: NSAttributedString? = nil
  if let d = pb.data(forType: .rtf) {
    attr = NSAttributedString(rtf: d, documentAttributes: nil)
  }
  if attr == nil, let d = pb.data(forType: .rtfd) {
    attr = NSAttributedString(rtfd: d, documentAttributes: nil)
  }
  if attr == nil, let d = pb.data(forType: NSPasteboard.PasteboardType("com.apple.flat-rtfd")) {
    attr = NSAttributedString(rtfd: d, documentAttributes: nil)
  }
  guard let a = attr, a.length > 0 else { return nil }
  return pellucidHtmlFromAttributed(a)
}
// END pellucidRtfToHtml
