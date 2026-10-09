// UNTESTED ON WINDOWS: written on a Mac, never compiled or run. See
// clipboard_channel.h.
#include "clipboard_channel.h"

#include <windows.h>

#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <cstring>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kChannelName[] = "com.overengineeredhobbies.pellucid/clipboard";
constexpr wchar_t kMarkdownFormatName[] = L"com.overengineeredhobbies.pellucid.markdown";
constexpr wchar_t kHtmlFormatName[] = L"HTML Format";

// Pasted text is capped so a hostile clipboard cannot make us copy gigabytes.
constexpr size_t kMaxPasteBytes = 64u * 1024u * 1024u;
// The CF_HTML header is a few short lines; offsets are looked up in this prefix.
constexpr size_t kMaxHeaderBytes = 1024;

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()),
                                    nullptr, 0);
  if (n <= 0) return std::wstring();
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.size()), out.data(), n);
  return out;
}

// Plain text for the clipboard uses CRLF line breaks.
std::string CrLf(const std::string& s) {
  std::string out;
  out.reserve(s.size() + s.size() / 8);
  for (size_t i = 0; i < s.size(); ++i) {
    if (s[i] == '\n' && (i == 0 || s[i - 1] != '\r')) out += '\r';
    out += s[i];
  }
  return out;
}

const std::string* StringArg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  if (it == args.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

// OpenClipboard / CloseClipboard as a scope. The clipboard can be briefly held
// by another process, so opening is retried a few times.
class ClipboardSession {
 public:
  ClipboardSession() {
    for (int attempt = 0; attempt < 5 && !open_; ++attempt) {
      open_ = OpenClipboard(nullptr) != FALSE;
      if (!open_) Sleep(10);
    }
  }
  ~ClipboardSession() {
    if (open_) CloseClipboard();
  }
  ClipboardSession(const ClipboardSession&) = delete;
  ClipboardSession& operator=(const ClipboardSession&) = delete;
  bool is_open() const { return open_; }

 private:
  bool open_ = false;
};

// GlobalAlloc / GlobalFree as a scope. release() hands the block to the
// clipboard after a successful SetClipboardData.
class GlobalMemory {
 public:
  explicit GlobalMemory(size_t size) : handle_(GlobalAlloc(GMEM_MOVEABLE, size)) {}
  ~GlobalMemory() {
    if (handle_) GlobalFree(handle_);
  }
  GlobalMemory(const GlobalMemory&) = delete;
  GlobalMemory& operator=(const GlobalMemory&) = delete;
  HGLOBAL get() const { return handle_; }
  HGLOBAL release() {
    HGLOBAL h = handle_;
    handle_ = nullptr;
    return h;
  }

 private:
  HGLOBAL handle_;
};

// GlobalLock / GlobalUnlock as a scope.
class GlobalLockGuard {
 public:
  explicit GlobalLockGuard(HGLOBAL handle)
      : handle_(handle), data_(handle ? GlobalLock(handle) : nullptr) {}
  ~GlobalLockGuard() {
    if (data_) GlobalUnlock(handle_);
  }
  GlobalLockGuard(const GlobalLockGuard&) = delete;
  GlobalLockGuard& operator=(const GlobalLockGuard&) = delete;
  void* data() const { return data_; }

 private:
  HGLOBAL handle_;
  void* data_;
};

// Puts `bytes` on the clipboard as `format`. The clipboard must be open and
// emptied by the caller. Ownership of the HGLOBAL passes to the clipboard on
// success.
bool SetClipboardBytes(UINT format, const void* bytes, size_t size) {
  GlobalMemory mem(size);
  if (!mem.get()) return false;
  {
    GlobalLockGuard lock(mem.get());
    if (!lock.data()) return false;
    std::memcpy(lock.data(), bytes, size);
  }
  if (!SetClipboardData(format, mem.get())) return false;
  mem.release();
  return true;
}

// The bytes of clipboard `format` up to the first NUL (text formats are stored
// NUL-terminated) and never past the block's real size. False when the format
// is absent, unreadable or larger than kMaxPasteBytes. The clipboard must be
// open.
bool ReadClipboardBytes(UINT format, std::string* out) {
  if (format == 0 || !IsClipboardFormatAvailable(format)) return false;
  HANDLE h = GetClipboardData(format);
  if (!h) return false;
  const SIZE_T size = GlobalSize(h);
  if (size == 0 || size > kMaxPasteBytes) return false;
  GlobalLockGuard lock(h);
  if (!lock.data()) return false;
  const char* p = static_cast<const char*>(lock.data());
  size_t n = 0;
  while (n < size && p[n] != '\0') ++n;
  out->assign(p, n);
  return true;
}

// Wraps an HTML fragment in the CF_HTML envelope. All offsets are byte
// offsets into the UTF-8 result, written as fixed-width 10-digit numbers so
// the header length does not depend on them.
std::string BuildCfHtml(const std::string& fragment) {
  const std::string prefix = "<html><body>\r\n<!--StartFragment-->";
  const std::string suffix = "<!--EndFragment-->\r\n</body></html>";
  const char header_fmt[] =
      "Version:0.9\r\nStartHTML:%010u\r\nEndHTML:%010u\r\n"
      "StartFragment:%010u\r\nEndFragment:%010u\r\n";
  char probe[128];
  const int header_len = std::snprintf(probe, sizeof(probe), header_fmt, 0u, 0u, 0u, 0u);
  const unsigned start_html = static_cast<unsigned>(header_len);
  const unsigned start_fragment = start_html + static_cast<unsigned>(prefix.size());
  const unsigned end_fragment = start_fragment + static_cast<unsigned>(fragment.size());
  const unsigned end_html = end_fragment + static_cast<unsigned>(suffix.size());
  std::snprintf(probe, sizeof(probe), header_fmt, start_html, end_html, start_fragment,
                end_fragment);
  return std::string(probe) + prefix + fragment + suffix;
}

// Reads the decimal number after `key` ("StartFragment:") in the header
// prefix of a CF_HTML block. False when the key is missing, has no digits,
// has more than 10 digits, or is not at the start of a line.
bool ReadHeaderOffset(const std::string& data, const char* key, size_t* value) {
  const size_t limit = data.size() < kMaxHeaderBytes ? data.size() : kMaxHeaderBytes;
  const std::string header = data.substr(0, limit);
  const size_t at = header.find(key);
  if (at == std::string::npos) return false;
  if (at != 0 && header[at - 1] != '\n') return false;
  size_t i = at + std::strlen(key);
  size_t v = 0;
  int digits = 0;
  while (i < header.size() && header[i] >= '0' && header[i] <= '9') {
    if (++digits > 10) return false;
    v = v * 10 + static_cast<size_t>(header[i] - '0');
    ++i;
  }
  if (digits == 0) return false;
  *value = v;
  return true;
}

// Extracts the fragment from a CF_HTML block. Every offset is bounds-checked
// against the data; anything inconsistent is rejected (false).
bool ExtractCfHtmlFragment(const std::string& data, std::string* fragment) {
  size_t start_fragment = 0, end_fragment = 0;
  if (!ReadHeaderOffset(data, "StartFragment:", &start_fragment)) return false;
  if (!ReadHeaderOffset(data, "EndFragment:", &end_fragment)) return false;
  if (start_fragment > end_fragment || end_fragment > data.size()) return false;
  // StartHTML / EndHTML are optional for us, but when present they must be sane
  // and enclose the fragment.
  size_t start_html = 0, end_html = data.size();
  const bool has_start = ReadHeaderOffset(data, "StartHTML:", &start_html);
  const bool has_end = ReadHeaderOffset(data, "EndHTML:", &end_html);
  if (has_start || has_end) {
    if (start_html > end_html || end_html > data.size()) return false;
    if (start_fragment < start_html || end_fragment > end_html) return false;
  }
  if (start_fragment == end_fragment) return false;
  fragment->assign(data, start_fragment, end_fragment - start_fragment);
  return true;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterClipboardChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        static const UINT markdown_format = RegisterClipboardFormatW(kMarkdownFormatName);
        static const UINT html_format = RegisterClipboardFormatW(kHtmlFormatName);

        if (call.method_name() == "setRich") {
          const auto* args = std::get_if<EncodableMap>(call.arguments());
          const std::string* plain = args ? StringArg(*args, "plain") : nullptr;
          const std::string* html = args ? StringArg(*args, "html") : nullptr;
          const std::string* markdown = args ? StringArg(*args, "markdown") : nullptr;
          if (!plain || !html || !markdown) {
            result->Error("bad_args", "plain, html and markdown required");
            return;
          }
          ClipboardSession session;
          if (!session.is_open()) {
            result->Error("clipboard_busy", "Could not open the clipboard");
            return;
          }
          EmptyClipboard();
          const std::wstring wide = Utf16FromUtf8(CrLf(*plain));
          bool ok = SetClipboardBytes(CF_UNICODETEXT, wide.c_str(),
                                      (wide.size() + 1) * sizeof(wchar_t));
          const std::string cf_html = BuildCfHtml(*html);
          ok = SetClipboardBytes(html_format, cf_html.c_str(), cf_html.size() + 1) && ok;
          ok = SetClipboardBytes(markdown_format, markdown->c_str(), markdown->size() + 1) && ok;
          if (!ok) {
            result->Error("clipboard_failed", "Could not write the clipboard");
            return;
          }
          result->Success();
        } else if (call.method_name() == "getMarkdown") {
          std::string out;
          ClipboardSession session;
          if (session.is_open() && ReadClipboardBytes(markdown_format, &out) && !out.empty()) {
            result->Success(EncodableValue(out));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "getHtml") {
          // "HTML Format" first, then nothing: Dart falls back to plain text.
          std::string raw, fragment;
          ClipboardSession session;
          if (session.is_open() && ReadClipboardBytes(html_format, &raw) &&
              ExtractCfHtmlFragment(raw, &fragment)) {
            result->Success(EncodableValue(fragment));
          } else {
            result->Success();
          }
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}
