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
      } else {
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
