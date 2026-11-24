/// Utility for upgrading low-resolution YouTube Music / Google CDN artwork to high-resolution.
class ThumbnailUtils {
  static final RegExp _googleUserContentSizePattern =
      RegExp(r'^(https://(?:lh3|yt3)\.googleusercontent\.com/[^?]*?)=(?:w\d+-h\d+|s\d+)[^?]*(\?.*)?$');

  static final RegExp _googleUserContentBasePattern =
      RegExp(r'^(https://(?:lh3|yt3)\.googleusercontent\.com/[^?=]+)(\?.*)?$');

  static final RegExp _ggphtSizePattern =
      RegExp(r'^(https://yt3\.ggpht\.com/[^?=]+)=(?:s\d+|w\d+-h\d+)[^?]*(\?.*)?$');

  static final RegExp _ggphtBasePattern =
      RegExp(r'^(https://yt3\.ggpht\.com/[^?=]+)(\?.*)?$');

  /// Upgrades low-resolution YouTube Music / Google CDN artwork to high-resolution.
  ///
  /// - For `lh3.googleusercontent.com` / `yt3.googleusercontent.com`:
  ///   rewrites size parameters to `=w$size-h$size-l90-rj`.
  /// - For `yt3.ggpht.com`:
  ///   rewrites size parameters to `=w$size-h$size-l90-rj`.
  /// - For `i.ytimg.com` / `i9.ytimg.com`:
  ///   upgrades `/default.jpg` or `/mqdefault.jpg` to `/hqdefault.jpg`.
  static String upgradeUrl(String? url, {int size = 544}) {
    if (url == null || url.trim().isEmpty) return '';
    final clean = url.trim();

    // 1. Google User Content (lh3/yt3)
    final gucMatch = _googleUserContentSizePattern.firstMatch(clean);
    if (gucMatch != null) {
      final base = gucMatch.group(1)!;
      final query = gucMatch.group(2) ?? '';
      return '$base=w$size-h$size-l90-rj$query';
    }
    if (clean.contains('googleusercontent.com')) {
      final baseMatch = _googleUserContentBasePattern.firstMatch(clean);
      if (baseMatch != null) {
        final base = baseMatch.group(1)!;
        final query = baseMatch.group(2) ?? '';
        return '$base=w$size-h$size-l90-rj$query';
      }
    }

    // 2. yt3.ggpht.com
    final ggphtMatch = _ggphtSizePattern.firstMatch(clean);
    if (ggphtMatch != null) {
      final base = ggphtMatch.group(1)!;
      final query = ggphtMatch.group(2) ?? '';
      return '$base=w$size-h$size-l90-rj$query';
    }
    if (clean.contains('ggpht.com')) {
      final baseMatch = _ggphtBasePattern.firstMatch(clean);
      if (baseMatch != null) {
        final base = baseMatch.group(1)!;
        final query = baseMatch.group(2) ?? '';
        return '$base=w$size-h$size-l90-rj$query';
      }
    }

    // 3. YouTube Video Thumbnails (i.ytimg.com / i9.ytimg.com)
    if (clean.contains('ytimg.com')) {
      if (clean.contains('/default.jpg')) {
        return clean.replaceAll('/default.jpg', '/hqdefault.jpg');
      }
      if (clean.contains('/mqdefault.jpg')) {
        return clean.replaceAll('/mqdefault.jpg', '/hqdefault.jpg');
      }
    }

    return clean;
  }
}
