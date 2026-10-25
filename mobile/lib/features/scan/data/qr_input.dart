/// Client-side pre-check of scanned text, mirroring the backend parser. The backend
/// remains the authority; this only lets the scanner reject non-VeriTrace QR codes instantly.
class QrInput {
  static final RegExp idPattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,39}$');

  /// Returns true for `veritrace://verify?id=…`, `http(s)://…/verify?id=…`, or a bare product ID.
  static bool isVeriTrace(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final scheme = uri.scheme.toLowerCase();
      final isApp = scheme == 'veritrace' && uri.host.toLowerCase() == 'verify';
      final isWeb = (scheme == 'http' || scheme == 'https') && RegExp(r'/verify/?$').hasMatch(uri.path);
      if (!isApp && !isWeb) return false;
      final id = (uri.queryParameters['id'] ?? '').trim().toUpperCase();
      return idPattern.hasMatch(id);
    }
    return idPattern.hasMatch(text.toUpperCase());
  }

  static String normalizeId(String raw) => raw.trim().toUpperCase();
}
