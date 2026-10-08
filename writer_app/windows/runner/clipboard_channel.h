#ifndef RUNNER_CLIPBOARD_CHANNEL_H_
#define RUNNER_CLIPBOARD_CHANNEL_H_

// ============================================================================
// UNTESTED ON WINDOWS, NOT COMPILED. Written on a Mac for slice 13 (1.1.0).
// This file and clipboard_channel.cpp are NOT listed in CMakeLists.txt and
// RegisterClipboardChannel is NOT called from flutter_window.cpp. To enable on
// the PC (docs/WINDOWS_1.1.0_HANDOFF.md): add clipboard_channel.cpp to the
// executable's sources, call RegisterClipboardChannel next to
// RegisterSpellCheckChannel, add TargetPlatform.windows to
// RichClipboard.isSupportedOn (lib/features/editor/rich_clipboard.dart), build
// and test. Until then Windows copies the markdown as plain text.
// ============================================================================

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Windows side of the "com.overengineeredhobbies.pellucid/clipboard" channel
// (macOS: MainFlutterWindow.swift, iOS: AppDelegate.swift).
//   setRich({plain, html, markdown}) -> null
//     CF_UNICODETEXT (plain), "HTML Format" (CF_HTML, html fragment) and a
//     private registered format "com.overengineeredhobbies.pellucid.markdown"
//     (UTF-8) in one clipboard transaction.
//   getMarkdown() -> String? (the private format, or null)
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterClipboardChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_CLIPBOARD_CHANNEL_H_
