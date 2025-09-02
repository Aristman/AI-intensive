import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void _debugLog(String msg) {
  if (kDebugMode) {
    debugPrint('[YandexSpeech] $msg');
  }
}

class _WavPcm {
  final Uint8List pcm;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  _WavPcm(this.pcm, this.sampleRate, this.channels, this.bitsPerSample);
}

_WavPcm? _tryExtractPcmFromWav(List<int> bytes) {
  try {
    if (bytes.length < 44) return null;
    final u = Uint8List.fromList(bytes);
    final bd = ByteData.sublistView(u);
    // Проверка заголовка RIFF/WAVE
    if (!(u[0] == 0x52 && u[1] == 0x49 && u[2] == 0x46 && u[3] == 0x46)) return null; // 'RIFF'
    if (!(u[8] == 0x57 && u[9] == 0x41 && u[10] == 0x56 && u[11] == 0x45)) return null; // 'WAVE'

    int offset = 12; // начало чанков
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? dataStart;
    int? dataSize;

    while (offset + 8 <= u.length) {
      final chunkId = String.fromCharCodes(u.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final next = offset + 8 + chunkSize;
      if (chunkId == 'fmt ') {
        // PCM fmt
        if (offset + 24 <= u.length) {
          final audioFormat = bd.getUint16(offset + 8, Endian.little); // 1 = PCM
          channels = bd.getUint16(offset + 10, Endian.little);
          sampleRate = bd.getUint32(offset + 12, Endian.little);
          bitsPerSample = bd.getUint16(offset + 22, Endian.little);
          if (audioFormat != 1) {
            _debugLog('WAV fmt: non-PCM format=$audioFormat');
          }
        }
      } else if (chunkId == 'data') {
        dataStart = offset + 8;
        dataSize = chunkSize;
      }
      offset = next;
      if (offset > u.length) break;
    }

    if (sampleRate == null || channels == null || bitsPerSample == null || dataStart == null || dataSize == null) {
      return null;
    }

    final end = (dataStart + dataSize) <= u.length ? (dataStart + dataSize) : u.length;
    final pcm = Uint8List.sublistView(u, dataStart, end);
    return _WavPcm(pcm, sampleRate, channels, bitsPerSample);
  } catch (e) {
    _debugLog('WAV parse error: $e');
    return null;
  }
}

String _hexHead(List<int> bytes, [int n = 12]) =>
    bytes.take(n).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

String _truncate(String s, [int n = 200]) => s.length <= n ? s : '${s.substring(0, n)}...';

class YandexSpeechService {
  static const _sttEndpoint = 'https://stt.api.cloud.yandex.net/speech/v1/stt:recognize';
  static const _ttsEndpoint = 'https://tts.api.cloud.yandex.net/speech/v1/tts:synthesize';

  String get _iamToken => dotenv.env['YANDEX_IAM_TOKEN'] ?? dotenv.env['YC_IAM_TOKEN'] ?? '';
  String get _apiKey => dotenv.env['YANDEX_API_KEY'] ?? '';
  String get _folderId => dotenv.env['YANDEX_FOLDER_ID'] ?? '';

  Map<String, String> _authHeaders() {
    if (_iamToken.isNotEmpty) {
      _debugLog('Auth: Bearer');
      return {
        'Authorization': 'Bearer $_iamToken',
      };
    }
    if (_apiKey.isNotEmpty) {
      _debugLog('Auth: Api-Key${_folderId.isNotEmpty ? ' + folderId' : ''}');
      return {
        'Authorization': 'Api-Key $_apiKey',
        if (_folderId.isNotEmpty) 'x-folder-id': _folderId,
      };
    }
    _debugLog('Auth: missing credentials');
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
      // WAV контейнер: для STT используем raw PCM (lpcm)
      qp['format'] = 'lpcm';
      // sampleRateHertz установим после чтения WAV заголовка
    } else if (ct.contains('ogg')) {
      qp['format'] = 'oggopus';
    } else if (ct.contains('lpcm') || ct.contains('pcm')) {
      qp['format'] = 'lpcm';
      qp['sampleRateHertz'] = '16000';
    }
    final uri = Uri.parse(_sttEndpoint).replace(queryParameters: qp);
    _debugLog('STT: file="$filePath", contentType=$contentType, query=$qp');

    final bytes = await file.readAsBytes();
    _debugLog('STT: size=${bytes.length} bytes, head=${_hexHead(bytes)}');

    List<int> bodyBytes = bytes;
    Map<String, String> headers;

    if (ct.contains('wav')) {
      // Пытаемся извлечь PCM из WAV
      final parsed = _tryExtractPcmFromWav(bytes);
      if (parsed != null) {
        bodyBytes = parsed.pcm;
        qp['sampleRateHertz'] = '${parsed.sampleRate}';
        // Пересобираем URI с добавленным sampleRate
        final newUri = Uri.parse(_sttEndpoint).replace(queryParameters: qp);
        _debugLog('STT: WAV->LPCM sr=${parsed.sampleRate}, ch=${parsed.channels}, bits=${parsed.bitsPerSample}');
        _debugLog('STT: POST ${newUri.toString()} (octet-stream, pcm=${bodyBytes.length} bytes)');
        headers = {
          ..._authHeaders(),
          'Content-Type': 'application/octet-stream',
        };
        final resp = await http.post(newUri, headers: headers, body: bodyBytes);
        if (resp.statusCode != 200) {
          _debugLog('STT: error status=${resp.statusCode}, body=${_truncate(resp.body)}');
          throw Exception('STT ошибка ${resp.statusCode}: ${resp.body}');
        }
        _debugLog('STT: status=${resp.statusCode}, bodyLen=${resp.bodyBytes.length}');
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = data['result'];
        if (result is String && result.isNotEmpty) {
          _debugLog('STT: ok, textLen=${result.length}');
          return result;
        }
        throw Exception('STT: пустой результат');
      } else {
        // Если не удалось распарсить WAV — пробуем отправить как есть, но с lpcm в формате может не сработать
        _debugLog('STT: WAV parse failed, sending raw WAV (may fail)');
        headers = {
          ..._authHeaders(),
          'Content-Type': contentType,
        };
        _debugLog('STT: POST ${uri.toString()}');
        final resp = await http.post(uri, headers: headers, body: bodyBytes);
        if (resp.statusCode != 200) {
          _debugLog('STT: error status=${resp.statusCode}, body=${_truncate(resp.body)}');
          throw Exception('STT ошибка ${resp.statusCode}: ${resp.body}');
        }
        _debugLog('STT: status=${resp.statusCode}, bodyLen=${resp.bodyBytes.length}');
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = data['result'];
        if (result is String && result.isNotEmpty) {
          _debugLog('STT: ok, textLen=${result.length}');
          return result;
        }
        throw Exception('STT: пустой результат');
      }
    } else {
      // Для oggopus/lpcm отправляем как есть
      headers = {
        ..._authHeaders(),
        'Content-Type': contentType,
      };
      _debugLog('STT: POST ${uri.toString()}');
      final resp = await http.post(uri, headers: headers, body: bodyBytes);
      if (resp.statusCode != 200) {
        _debugLog('STT: error status=${resp.statusCode}, body=${_truncate(resp.body)}');
        throw Exception('STT ошибка ${resp.statusCode}: ${resp.body}');
      }
      _debugLog('STT: status=${resp.statusCode}, bodyLen=${resp.bodyBytes.length}');
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = data['result'];
      if (result is String && result.isNotEmpty) {
        _debugLog('STT: ok, textLen=${result.length}');
        return result;
      }
      throw Exception('STT: пустой результат');
    }
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

    // Для lpcm зададим частоту дискретизации, чтобы знать параметры PCM для упаковки в WAV
    final int lpcmSampleRate = 16000;

    final bodyParams = {
      'text': text,
      'voice': voice,
      'lang': lang,
      'format': format,
      'speed': speed.toString(),
      if (format == 'lpcm') 'sampleRateHertz': '$lpcmSampleRate',
      if (_iamToken.isEmpty && _folderId.isNotEmpty) 'folderId': _folderId,
    };

    _debugLog('TTS: params voice=$voice, lang=$lang, format=$format, speed=$speed, textLen=${text.length}');

    final resp = await http.post(
      Uri.parse(_ttsEndpoint),
      headers: headers,
      body: bodyParams,
      encoding: Encoding.getByName('utf-8'),
    );

    if (resp.statusCode != 200) {
      _debugLog('TTS: error status=${resp.statusCode}, body=${_truncate(resp.body)}');
      throw Exception('TTS ошибка ${resp.statusCode}: ${resp.body}');
    }

    // Сохраняем аудио во временный файл
    final tempDir = await getTemporaryDirectory();
    final ext = format == 'oggopus' ? 'ogg' : (format == 'lpcm' ? 'wav' : 'bin');
    final sep = Platform.pathSeparator;
    final file = File('${tempDir.path}${sep}tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
    if (format == 'lpcm') {
      // Ответ — сырые PCM (16-bit LE), упакуем в WAV для воспроизведения на Windows
      final wavBytes = _pcmToWav(Uint8List.fromList(resp.bodyBytes),
          sampleRate: lpcmSampleRate, channels: 1, bitsPerSample: 16);
      await file.writeAsBytes(wavBytes, flush: true);
      _debugLog('TTS: status=${resp.statusCode}, saved="${file.path}" (WAV from PCM), size=${wavBytes.length} bytes');
    } else {
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      _debugLog('TTS: status=${resp.statusCode}, saved="${file.path}", size=${resp.bodyBytes.length} bytes');
    }
    return file.path;
  }
}

Uint8List _pcmToWav(Uint8List pcm,
    {required int sampleRate, required int channels, required int bitsPerSample}) {
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final dataSize = pcm.length;
  final riffChunkSize = 36 + dataSize;

  final header = BytesBuilder();
  // RIFF header
  header.add([0x52, 0x49, 0x46, 0x46]); // 'RIFF'
  header.add(_u32le(riffChunkSize));
  header.add([0x57, 0x41, 0x56, 0x45]); // 'WAVE'
  // fmt chunk
  header.add([0x66, 0x6d, 0x74, 0x20]); // 'fmt '
  header.add(_u32le(16)); // PCM fmt chunk size
  header.add(_u16le(1)); // audioFormat = 1 (PCM)
  header.add(_u16le(channels));
  header.add(_u32le(sampleRate));
  header.add(_u32le(byteRate));
  header.add(_u16le(blockAlign));
  header.add(_u16le(bitsPerSample));
  // data chunk
  header.add([0x64, 0x61, 0x74, 0x61]); // 'data'
  header.add(_u32le(dataSize));

  final wav = BytesBuilder();
  wav.add(header.toBytes());
  wav.add(pcm);
  return Uint8List.fromList(wav.toBytes());
}

List<int> _u16le(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32le(int v) => [
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ];
