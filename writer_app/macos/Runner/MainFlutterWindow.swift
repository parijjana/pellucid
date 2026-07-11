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
