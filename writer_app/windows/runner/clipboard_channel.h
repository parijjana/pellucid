#ifndef RUNNER_CLIPBOARD_CHANNEL_H_
#define RUNNER_CLIPBOARD_CHANNEL_H_

// ============================================================================
// UNTESTED ON WINDOWS. Written on a Mac for 1.1.0 and never compiled or run
// here. Build and check it on the PC (docs/WINDOWS_1.1.0_HANDOFF.md). The
// CF_HTML header offsets are the likeliest thing to need a fix.
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
//   getHtml() -> String? (the fragment of "HTML Format" as UTF-8 HTML, or
//     null when absent or the CF_HTML header is malformed)
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterClipboardChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_CLIPBOARD_CHANNEL_H_
