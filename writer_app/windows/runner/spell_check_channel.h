#ifndef RUNNER_SPELL_CHECK_CHANNEL_H_
#define RUNNER_SPELL_CHECK_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Windows side of the "com.overengineeredhobbies.pellucid/spellcheck" channel
// (the macOS side lives in MainFlutterWindow.swift). Backed by the system
// spell checker (ISpellChecker, Windows 8+), so it honours the user's
// installed languages and their "Add to dictionary" words.
//
// checkSpelling({text, language, locale}) -> [{start, end, suggestions}],
// offsets in UTF-16 code units, the same shape the Swift handler returns.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterSpellCheckChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SPELL_CHECK_CHANNEL_H_
