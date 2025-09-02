import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class YandexSpeechService {
  static const _sttEndpoint = 'https://stt.api.cloud.yandex.net/speech/v1/stt:recognize';
  static const _ttsEndpoint = 'https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize';

  String get _iamToken => dotenv.env['YANDEX_IAM_TOKEN'] ?? dotenv.env['YC_IAM_TOKEN'] ?? '';
  String get _apiKey => dotenv.env['YANDEX_API_KEY'] ?? '';
  String get _folderId => dotenv.env['YANDEX_FOLDER_ID'] ?? '';

  Map<String, String> _authHeaders() {
    if (_iamToken.isNotEmpty) {
      return {
        'Authorization': 'Bearer $_iamToken',
      };
    }
    if (_apiKey.isNotEmpty) {
      return {
        'Authorization': 'Api-Key $_apiKey',
        if (_folderId.isNotEmpty) 'x-folder-id': _folderId,
      };
    }
    throw Exception('Не найден Yandex IAM токен или API ключ в assets/.env');
  }

  Future<String> recognizeSpeech(String filePath, {String lang = 'ru-RU', String contentType = 'audio/ogg'}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Аудиофайл не найден: $filePath');
    }

    // Подберём корректный формат для STT на основе contentType
    final qp = <String, String>{'lang': lang};
    final ct = contentType.toLowerCase();
    if (ct.contains('wav')) {
      qp['format'] = 'wav';
    } else if (ct.contains('ogg')) {
      qp['format'] = 'oggopus';
    } else if (ct.contains('lpcm') || ct.contains('pcm')) {
      qp['format'] = 'lpcm';
      qp['sampleRateHertz'] = '16000';
    }
    final uri = Uri.parse(_sttEndpoint).replace(queryParameters: qp);
    final headers = {
      ..._authHeaders(),
      'Content-Type': contentType,
    };

    final bytes = await file.readAsBytes();
    final resp = await http.post(uri, headers: headers, body: bytes);

    if (resp.statusCode != 200) {
      throw Exception('STT ошибка ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'];
    if (result is String && result.isNotEmpty) {
      return result;
    }
    throw Exception('STT: пустой результат');
  }

  Future<String> synthesizeSpeech(
    String text, {
    String voice = 'alena',
    String lang = 'ru-RU',
    String format = 'oggopus',
    double speed = 1.0,
  }) async {
    if (text.trim().isEmpty) {
      throw Exception('TTS: пустой текст');
    }

    final headers = {
      ..._authHeaders(),
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    final bodyParams = {
      'text': text,
      'voice': voice,
      'lang': lang,
      'format': format,
      'speed': speed.toString(),
      if (_iamToken.isEmpty && _folderId.isNotEmpty) 'folderId': _folderId,
    };

    final resp = await http.post(
      Uri.parse(_ttsEndpoint),
      headers: headers,
      body: bodyParams,
      encoding: Encoding.getByName('utf-8'),
    );

    if (resp.statusCode != 200) {
      throw Exception('TTS ошибка ${resp.statusCode}: ${resp.body}');
    }

    // Сохраняем аудио во временный файл
    final tempDir = await getTemporaryDirectory();
    final ext = format == 'oggopus' ? 'ogg' : (format == 'lpcm' ? 'wav' : 'bin');
    final file = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(resp.bodyBytes, flush: true);
    return file.path;
  }
}
