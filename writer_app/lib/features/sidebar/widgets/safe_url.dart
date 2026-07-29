// Shared helper for validating user-supplied URLs (note source URLs,
// attribution text links) before handing them to url_launcher. Restricts
// launches to http/https so a stored `file://`, `javascript:`, or other
// custom-scheme URL can never be invoked.

/// Normalizes [rawUrl] (trimming it and, if it starts with `www.`,
/// prepending `https://`) and returns the resulting [Uri] only if it parses
/// and its scheme is `http` or `https`. Returns null otherwise, meaning the
/// URL must not be launched.
Uri? safeHttpUri(String rawUrl) {
  var url = rawUrl.trim();
  if (url.isEmpty) return null;
  if (url.startsWith('www.')) {
    url = 'https://$url';
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}
