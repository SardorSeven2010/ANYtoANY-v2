import 'dart:async';
import 'dart:io';

/// Yuklashni bekor qilish belgisi. Bekor qilinganda ochiq ulanishlar yopiladi.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _hooks = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final hook in List.of(_hooks)) {
      try {
        hook();
      } catch (_) {}
    }
    _hooks.clear();
  }

  /// Bekor qilinganda chaqiriladi. Qaytarilgan funksiya ro'yxatdan olib tashlaydi.
  void Function() onCancel(void Function() hook) {
    if (_cancelled) {
      hook();
      return () {};
    }
    _hooks.add(hook);
    return () => _hooks.remove(hook);
  }

  void throwIfCancelled() {
    if (_cancelled) throw const DownloadCancelled();
  }
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => "Yuklash bekor qilindi";
}

/// Foydalanuvchiga ko'rsatiladigan yuklash xatosi
class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
  @override
  String toString() => message;
}

/// Brauzerga o'xshash sarlavhalar: ko'p saytlar oddiy "Dart" mijozini rad etadi
const String defaultUserAgent =
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36";

HttpClient newHttpClient() => HttpClient()
  ..autoUncompress = false // hajm Content-Length bilan mos kelishi uchun siqilmagan holda olinadi
  ..connectionTimeout = const Duration(seconds: 20)
  ..idleTimeout = const Duration(seconds: 15)
  ..userAgent = defaultUserAgent;

/// Tarmoq xatosi qayta urinib ko'rishga arziydimi
bool isRetryable(Object error) =>
    error is SocketException ||
    error is HttpException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is TlsException ||
    error is _RetryableStatus;

class _RetryableStatus implements Exception {
  final int status;
  const _RetryableStatus(this.status);
  @override
  String toString() => "Server javobi: $status";
}

/// HTTP holatiga qarab: 5xx va 429 - qayta urinish, 4xx - to'xtash
void checkStatus(HttpClientResponse response, {Set<int> ok = const {200, 206}}) {
  final s = response.statusCode;
  if (ok.contains(s)) return;
  if (s >= 500 || s == 429 || s == 408) throw _RetryableStatus(s);
  if (s == 401 || s == 403) throw DownloadException("Sayt yuklashga ruxsat bermadi ($s). Havola muddati tugagan bo'lishi mumkin.");
  if (s == 404 || s == 410) throw DownloadException("Fayl topilmadi ($s). Havola eskirgan bo'lishi mumkin.");
  throw DownloadException("Server xato qaytardi ($s)");
}

/// Fayl nomi uchun yaroqsiz belgilarni almashtiradi
String safeFileName(String name, {int maxLength = 80}) {
  var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'^\.+'), '');
  if (s.length > maxLength) s = s.substring(0, maxLength).trim();
  return s.isEmpty ? "video" : s;
}

/// Content-Disposition sarlavhasidagi fayl nomi
String? fileNameFromDisposition(String? header) {
  if (header == null) return null;
  final star = RegExp(r"filename\*\s*=\s*[^']*'[^']*'([^;]+)", caseSensitive: false).firstMatch(header);
  if (star != null) {
    try {
      return Uri.decodeComponent(star.group(1)!.trim());
    } catch (_) {}
  }
  final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?', caseSensitive: false).firstMatch(header);
  return plain?.group(1)?.trim();
}
