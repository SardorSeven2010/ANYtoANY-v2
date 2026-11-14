import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Hujjatlarni internet orqali aylantirish:
///   PDF -> Word / PowerPoint / Excel  va  Word / PowerPoint / Excel -> PDF.
/// Tashqi xizmat kaliti ilovada emas, Supabase Edge Function ichida saqlanadi.

enum OnlineOperation {
  /// PDF dan boshqa hujjatga
  export,

  /// Hujjatdan PDF ga
  create,
}

/// PDF ga aylantirish mumkin bo'lgan hujjat turlari
const List<String> onlineSourceFormats = ["doc", "docx", "ppt", "pptx", "xls", "xlsx", "rtf", "txt"];

class OnlineTarget {
  final String format;
  final String title;
  const OnlineTarget(this.format, this.title);
}

const List<OnlineTarget> onlineTargets = [
  OnlineTarget("docx", "Word"),
  OnlineTarget("pptx", "PowerPoint"),
  OnlineTarget("xlsx", "Excel"),
];

class OnlinePdfException implements Exception {
  final String message;
  const OnlinePdfException(this.message);

  @override
  String toString() => message;
}

String _messageFor(String code, [String? detail]) {
  switch (code) {
    case "unauthorized":
      return "Avval ilovaga qaytadan kiring.";
    case "pro_required":
      return "Bu imkoniyat faqat PRO obunachilar uchun.";
    case "daily_limit":
      return "Bugungi limit tugadi. Ertaga qayta urinib ko'ring.";
    case "not_configured":
      return "Konvertatsiya xizmati hali sozlanmagan.";
    case "provider_quota":
      return "Konvertatsiya xizmatining limiti tugagan. Keyinroq urinib ko'ring.";
    default:
      return (detail == null || detail.isEmpty) ? "Konvertatsiya xizmatida xatolik yuz berdi." : detail;
  }
}

/// Edge Function ni chaqiradigan funksiya turi (sinovda almashtirish uchun)
typedef FunctionInvoker = Future<Map<String, dynamic>> Function(Map<String, dynamic> body);

Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
  try {
    final response = await Supabase.instance.client.functions.invoke(convertFunctionName, body: body);
    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const OnlinePdfException("Serverdan kutilmagan javob keldi.");
  } on FunctionException catch (e) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      throw OnlinePdfException(_messageFor(details['error'] as String, details['message']?.toString()));
    }
    if (e.status == 404) throw OnlinePdfException(_messageFor("not_configured"));
    if (e.status == 401) throw OnlinePdfException(_messageFor("unauthorized"));
    throw OnlinePdfException("Server xatosi (${e.status}).");
  }
}

Future<void> _upload(String url, File file, String mediaType) async {
  final client = HttpClient();
  try {
    final request = await client.putUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.contentTypeHeader, mediaType);
    request.contentLength = await file.length();
    await request.addStream(file.openRead());
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OnlinePdfException("Faylni yuklab bo'lmadi (${response.statusCode}).");
    }
  } finally {
    client.close();
  }
}

Future<void> _download(String url, String outPath) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw OnlinePdfException("Tayyor faylni olib bo'lmadi (${response.statusCode}).");
    }
    await response.pipe(File(outPath).openWrite());
  } finally {
    client.close();
  }
}

/// [sourcePath] dagi faylni aylantirib, [outPath] ga saqlaydi.
///
/// [OnlineOperation.export]: PDF -> [targetFormat] (docx / pptx / xlsx).
/// [OnlineOperation.create]: [sourceFormat] turidagi hujjat -> PDF.
Future<void> convertOnline({
  required String sourcePath,
  required String outPath,
  OnlineOperation operation = OnlineOperation.export,
  String? targetFormat,
  String? sourceFormat,
  void Function(String stage)? onStage,
  FunctionInvoker? invoke,
  Duration pollInterval = const Duration(seconds: 2),
}) async {
  final FunctionInvoker call = invoke ?? _call;
  final Map<String, dynamic> request = {
    "operation": operation.name,
    if (operation == OnlineOperation.export) "targetFormat": targetFormat,
    if (operation == OnlineOperation.create) "sourceFormat": sourceFormat,
  };

  onStage?.call("Tayyorlanmoqda...");
  final start = await call({"action": "start", ...request});

  onStage?.call("Fayl yuklanmoqda...");
  await _upload(
    start["uploadUri"].toString(),
    File(sourcePath),
    (start["mediaType"] ?? "application/pdf").toString(),
  );

  onStage?.call("Aylantirilmoqda...");
  final job = await call({"action": "convert", "assetID": start["assetID"], ...request});

  final deadline = DateTime.now().add(const Duration(minutes: 4));
  while (true) {
    await Future<void>.delayed(pollInterval);
    final status = await call({
      "action": "status",
      "operation": operation.name,
      "jobId": job["jobId"],
      "host": job["host"],
    });
    if (status["status"] == "done") {
      onStage?.call("Saqlanmoqda...");
      await _download(status["downloadUri"].toString(), outPath);
      return;
    }
    if (status["status"] == "failed") {
      throw OnlinePdfException(_messageFor("provider_error", status["message"]?.toString()));
    }
    if (DateTime.now().isAfter(deadline)) {
      throw const OnlinePdfException("Konvertatsiya juda uzoq davom etdi. Keyinroq urinib ko'ring.");
    }
  }
}
