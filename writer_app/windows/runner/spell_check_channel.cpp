#include "spell_check_channel.h"

#include <windows.h>
#include <objidl.h>
#include <spellcheck.h>
#include <wrl/client.h>

#include <flutter/standard_method_codec.h>

#include <map>
#include <string>
#include <vector>

#include "utils.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

constexpr char kChannelName[] = "com.overengineeredhobbies.pellucid/spellcheck";
constexpr size_t kMaxSuggestions = 5;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring utf16(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                        static_cast<int>(utf8.size()), utf16.data(), length);
  return utf16;
}

const std::string* StringArg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  if (it == args.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

class WindowsSpellChecker {
 public:
  // The whole document is re-checked on every edit, so the same misspelled
  // names come back again and again: suggestions are cached per language+word.
  EncodableList Check(const std::wstring& text,
                      const std::vector<std::wstring>& languages) {
    EncodableList results;
    ISpellChecker* checker = CheckerFor(languages);
    if (!checker || text.empty()) return results;

    ComPtr<IEnumSpellingError> errors;
    if (FAILED(checker->ComprehensiveCheck(text.c_str(), &errors)) || !errors) {
      return results;
    }

    ComPtr<ISpellingError> error;
    while (errors->Next(&error) == S_OK) {
      ULONG start = 0, length = 0;
      CORRECTIVE_ACTION action = CORRECTIVE_ACTION_NONE;
      error->get_StartIndex(&start);
      error->get_Length(&length);
      error->get_CorrectiveAction(&action);

      // CORRECTIVE_ACTION_DELETE is the repeated-word check ("the the"),
      // which NSSpellChecker does not flag either; skip it for parity.
      if (length > 0 && start + length <= text.size() &&
          (action == CORRECTIVE_ACTION_GET_SUGGESTIONS ||
           action == CORRECTIVE_ACTION_REPLACE)) {
        EncodableList suggestions;
        if (action == CORRECTIVE_ACTION_REPLACE) {
          PWSTR replacement = nullptr;
          if (SUCCEEDED(error->get_Replacement(&replacement)) && replacement) {
            suggestions.emplace_back(Utf8FromUtf16(replacement));
            ::CoTaskMemFree(replacement);
          }
        } else {
          suggestions = Suggest(checker, text.substr(start, length));
        }
        results.emplace_back(EncodableMap{
            {EncodableValue("start"), EncodableValue(static_cast<int32_t>(start))},
            {EncodableValue("end"),
             EncodableValue(static_cast<int32_t>(start + length))},
            {EncodableValue("suggestions"), EncodableValue(suggestions)},
        });
      }
      error.Reset();
    }
    return results;
  }

  // UNTESTED ON WINDOWS (written on a Mac): adds the word to the user
  // dictionary (ISpellChecker::Add) or ignores it for this session
  // (ISpellChecker::Ignore).
  bool WordAction(const std::wstring& word,
                  const std::vector<std::wstring>& languages, bool learn) {
    ISpellChecker* checker = CheckerFor(languages);
    if (!checker || word.empty()) return false;
    return SUCCEEDED(learn ? checker->Add(word.c_str())
                           : checker->Ignore(word.c_str()));
  }

 private:
  // First supported tag wins: the Flutter locale ("en-US"), then the bare
  // language ("en"), then the Windows display language, then en-US.
  ISpellChecker* CheckerFor(const std::vector<std::wstring>& languages) {
    if (!factory_ && FAILED(::CoCreateInstance(__uuidof(SpellCheckerFactory),
                                               nullptr, CLSCTX_INPROC_SERVER,
                                               IID_PPV_ARGS(&factory_)))) {
      return nullptr;
    }
    std::vector<std::wstring> candidates = languages;
    wchar_t user_locale[LOCALE_NAME_MAX_LENGTH] = {};
    if (::GetUserDefaultLocaleName(user_locale, LOCALE_NAME_MAX_LENGTH) > 0) {
      candidates.emplace_back(user_locale);
    }
    candidates.emplace_back(L"en-US");

    for (const auto& tag : candidates) {
      if (tag.empty()) continue;
      auto cached = checkers_.find(tag);
      if (cached != checkers_.end()) {
        current_tag_ = tag;
        return cached->second.Get();
      }
      BOOL supported = FALSE;
      if (FAILED(factory_->IsSupported(tag.c_str(), &supported)) || !supported) {
        continue;
      }
      ComPtr<ISpellChecker> checker;
      if (SUCCEEDED(factory_->CreateSpellChecker(tag.c_str(), &checker))) {
        current_tag_ = tag;
        return (checkers_[tag] = checker).Get();
      }
    }
    return nullptr;
  }

  EncodableList Suggest(ISpellChecker* checker, const std::wstring& word) {
    const std::wstring key = current_tag_ + L"|" + word;
    auto cached = suggestions_.find(key);
    if (cached != suggestions_.end()) return cached->second;

    EncodableList suggestions;
    ComPtr<IEnumString> words;
    if (SUCCEEDED(checker->Suggest(word.c_str(), &words)) && words) {
      LPOLESTR suggestion = nullptr;
      while (suggestions.size() < kMaxSuggestions &&
             words->Next(1, &suggestion, nullptr) == S_OK) {
        suggestions.emplace_back(Utf8FromUtf16(suggestion));
        ::CoTaskMemFree(suggestion);
      }
    }
    if (suggestions_.size() > 5000) suggestions_.clear();
    return suggestions_[key] = suggestions;
  }

  ComPtr<ISpellCheckerFactory> factory_;
  std::map<std::wstring, ComPtr<ISpellChecker>> checkers_;
  std::wstring current_tag_;
  std::map<std::wstring, EncodableList> suggestions_;
};

}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>>
RegisterSpellCheckChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  auto checker = std::make_shared<WindowsSpellChecker>();

  channel->SetMethodCallHandler(
      [checker](const flutter::MethodCall<EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const bool is_word_action =
            call.method_name() == "learnWord" || call.method_name() == "ignoreWord";
        if (call.method_name() != "checkSpelling" && !is_word_action) {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        if (is_word_action) {  // untested on Windows
          const std::string* word = args ? StringArg(*args, "word") : nullptr;
          std::vector<std::wstring> langs;
          if (args) {
            if (const auto* locale = StringArg(*args, "locale")) {
              langs.push_back(Utf16FromUtf8(*locale));
            }
            if (const auto* language = StringArg(*args, "language")) {
              langs.push_back(Utf16FromUtf8(*language));
            }
          }
          result->Success(EncodableValue(
              word && checker->WordAction(Utf16FromUtf8(*word), langs,
                                          call.method_name() == "learnWord")));
          return;
        }
        const std::string* text = args ? StringArg(*args, "text") : nullptr;
        if (!text) {
          result->Success(EncodableValue(EncodableList()));
          return;
        }
        std::vector<std::wstring> languages;
        if (const auto* locale = StringArg(*args, "locale")) {
          languages.push_back(Utf16FromUtf8(*locale));
        }
        if (const auto* language = StringArg(*args, "language")) {
          languages.push_back(Utf16FromUtf8(*language));
        }
        result->Success(
            EncodableValue(checker->Check(Utf16FromUtf8(*text), languages)));
      });
  return channel;
}
