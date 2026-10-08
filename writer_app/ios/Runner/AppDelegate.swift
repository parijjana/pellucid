import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PellucidNativeChannels") {
      registerSpellCheckChannel(messenger: registrar.messenger())
      registerClipboardChannel(messenger: registrar.messenger())
    }
  }

  // Same channel and methods as macos/Runner/MainFlutterWindow.swift, backed by
  // UITextChecker. Dart: lib/features/editor/services/native_spell_check_service.dart.
  private func registerSpellCheckChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.overengineeredhobbies.pellucid/spellcheck",
      binaryMessenger: messenger
    )
    // One checker for the session: ignoreWord is per UITextChecker instance.
    let checker = UITextChecker()
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "checkSpelling":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String else {
          result([])
          return
        }
        let language = args["language"] as? String ?? "en"
        let length = (text as NSString).length
        var results: [[String: Any]] = []
        var offset = 0
        while offset < length {
          let range = checker.rangeOfMisspelledWord(
            in: text,
            range: NSRange(location: offset, length: length - offset),
            startingAt: offset,
            wrap: false,
            language: language
          )
          if range.location == NSNotFound || range.length == 0 || range.location < offset {
            break
          }
          let guesses = checker.guesses(forWordRange: range, in: text, language: language) ?? []
          results.append([
            "start": range.location,
            "end": range.location + range.length,
            "suggestions": guesses,
          ])
          offset = range.location + range.length
        }
        result(results)
      case "learnWord", "ignoreWord":
        // One word only, as on the Dart side (isLearnableWord): 1-64 code
        // points, no whitespace or control characters. learnWord writes the
        // user's dictionary, so reject anything else here too.
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
          UITextChecker.learnWord(word)
        } else {
          checker.ignoreWord(word)
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Copy from the editor: HTML + plain text for other apps, plus the markdown
  // under a private type so a paste inside Pellucid keeps it. Mirrors the macOS
  // "clipboard" channel (setRich / getMarkdown).
  private func registerClipboardChannel(messenger: FlutterBinaryMessenger) {
    let markdownType = "com.overengineeredhobbies.pellucid.markdown"
    let channel = FlutterMethodChannel(
      name: "com.overengineeredhobbies.pellucid/clipboard",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { (call, result) in
      let pasteboard = UIPasteboard.general
      switch call.method {
      case "setRich":
        guard let args = call.arguments as? [String: Any],
              let plain = args["plain"] as? String,
              let html = args["html"] as? String,
              let markdown = args["markdown"] as? String else {
          result(FlutterError(code: "bad_args", message: "plain, html and markdown required", details: nil))
          return
        }
        pasteboard.setItems([[
          "public.utf8-plain-text": plain,
          "public.html": "<meta charset=\"utf-8\">" + html,
          markdownType: markdown,
        ]], options: [:])
        result(nil)
      case "getMarkdown":
        if let data = pasteboard.data(forPasteboardType: markdownType) {
          result(String(data: data, encoding: .utf8))
        } else {
          result(pasteboard.value(forPasteboardType: markdownType) as? String)
        }
      case "getHtml":
        // Pasting formatted text (item 22): the HTML other apps put on the pasteboard.
        if let data = pasteboard.data(forPasteboardType: "public.html") {
          result(String(data: data, encoding: .utf8))
        } else {
          result(pasteboard.value(forPasteboardType: "public.html") as? String)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
