import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sample_app/agents/workspace/workspace_file_entities.dart';

/// FileSystemService: безопасные операции в пределах корня `rootDir`.
/// Защита от выхода за пределы корня с нормализацией путей.
class FileSystemService {
  final String rootDir; // абсолютный путь к корню песочницы

  FileSystemService(String root)
      : rootDir = p.normalize(p.absolute(root));

  /// Преобразует входной путь (относительный или абсолютный) к абсолютному
  /// в пределах корня. Бросает [FileSystemException] при выходе за пределы корня.
  String resolveInsideRoot(String inputPath) {
    if (inputPath.trim().isEmpty) {
      throw FileSystemException('Путь не задан');
    }
    final candidateAbs = p.normalize(
      p.isAbsolute(inputPath) ? inputPath : p.join(rootDir, inputPath),
    );
    if (!_isWithinRoot(candidateAbs)) {
      throw FileSystemException('Выход за пределы корня запрещён', candidateAbs);
    }
    return candidateAbs;
  }

  bool _isWithinRoot(String absPath) {
    final rp = p.normalize(p.absolute(absPath));
    final rr = p.normalize(p.absolute(rootDir));
    return p.isWithin(rr, rp) || p.equals(rp, rr);
  }

  /// Список содержимого директории.
  Future<DirListing> list(String path) async {
    try {
      final abs = resolveInsideRoot(path);
      final dir = Directory(abs);
      if (!await dir.exists()) {
        return DirListing(path: _rel(abs), entries: [], message: 'Директория не найдена: ${_rel(abs)}');
      }
      final children = await dir.list().toList();
      final entries = <DirEntry>[];
      for (final e in children) {
        if (e is Directory) {
          entries.add(DirEntry(name: p.basename(e.path), isDir: true));
        } else if (e is File) {
          final size = await e.length();
          entries.add(DirEntry(name: p.basename(e.path), isDir: false, size: size));
        }
      }
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return DirListing(path: _rel(abs), entries: entries);
    } on FileSystemException catch (e) {
      return DirListing(path: path, entries: [], message: 'Ошибка доступа: ${e.message} (${e.path ?? ''})');
    } catch (e) {
      return DirListing(path: path, entries: [], message: 'Ошибка чтения директории: $e');
    }
  }

  static const int _maxPreviewBytes = 64 * 1024; // 64KB

  /// Читает файл с ограничением превью.
  Future<FilePreview> readFile(String path) async {
    try {
      final abs = resolveInsideRoot(path);
      final f = File(abs);
      if (!await f.exists()) {
        return FilePreview(
          path: _rel(abs),
          exists: false,
          isDir: false,
          size: 0,
          contentSnippet: '',
          message: 'Файл не найден: ${_rel(abs)}',
        );
      }
      final length = await f.length();
      final stream = f.openRead(0, length > _maxPreviewBytes ? _maxPreviewBytes : null);
      final bytes = await stream.fold<List<int>>(<int>[], (p, e) => (p..addAll(e)));
      final content = String.fromCharCodes(bytes);
      final snippet = content.length > 2000 ? content.substring(0, 2000) + '\n…' : content;
      final msg = 'Файл: ${_rel(abs)}\nРазмер: $length байт\n\n--- Содержимое (превью) ---\n$snippet';
      return FilePreview(
        path: _rel(abs),
        exists: true,
        isDir: false,
        size: length,
        contentSnippet: snippet,
        message: msg,
      );
    } on FileSystemException catch (e) {
      return FilePreview(
        path: path,
        exists: false,
        isDir: false,
        size: 0,
        contentSnippet: '',
        message: 'Ошибка доступа: ${e.message} (${e.path ?? ''})',
      );
    } catch (e) {
      return FilePreview(
        path: path,
        exists: false,
        isDir: false,
        size: 0,
        contentSnippet: '',
        message: 'Ошибка чтения файла: $e',
      );
    }
  }

  /// Записывает файл. Если `overwrite=false` и файл существует — вернёт ошибку.
  Future<FileOpResult> writeFile({
    required String path,
    required String content,
    bool createDirs = false,
    bool overwrite = false,
  }) async {
    try {
      final abs = resolveInsideRoot(path);
      final file = File(abs);
      if (await file.exists() && !overwrite) {
        return FileOpResult(
          success: false,
          path: _rel(abs),
          bytesWritten: 0,
          message: 'Файл уже существует. Установите overwrite=true для перезаписи.',
        );
      }
      if (createDirs) {
        await file.parent.create(recursive: true);
      }
      final bytes = content.codeUnits.length;
      await file.writeAsString(content, mode: FileMode.write, flush: true);
      return FileOpResult(
        success: true,
        path: _rel(abs),
        bytesWritten: bytes,
        message: 'Записано $bytes байт в ${_rel(abs)}',
      );
    } on FileSystemException catch (e) {
      return FileOpResult(success: false, path: path, bytesWritten: 0, message: 'Ошибка доступа: ${e.message} (${e.path ?? ''})');
    } catch (e) {
      return FileOpResult(success: false, path: path, bytesWritten: 0, message: 'Ошибка записи файла: $e');
    }
  }

  /// Удаление файла или директории. Для директории требуется `recursive=true`.
  Future<FileOpResult> deletePath(String path, {bool recursive = false}) async {
    try {
      final abs = resolveInsideRoot(path);
      final type = FileSystemEntity.typeSync(abs);
      if (type == FileSystemEntityType.notFound) {
        return const FileOpResult(success: true, path: '', bytesWritten: 0, message: 'Нечего удалять — путь не найден');
      }
      if (type == FileSystemEntityType.directory) {
        final dir = Directory(abs);
        if (!recursive) {
          // Проверим, пустая ли директория
          final isEmpty = await dir.list().isEmpty;
          if (!isEmpty) {
            return FileOpResult(
              success: false,
              path: _rel(abs),
              bytesWritten: 0,
              message: 'Директория не пуста. Укажите recursive=true для рекурсивного удаления.',
            );
          }
        }
        await dir.delete(recursive: recursive);
        return FileOpResult(success: true, path: _rel(abs), bytesWritten: 0, message: 'Удалено: ${_rel(abs)}');
      } else {
        final f = File(abs);
        await f.delete();
        return FileOpResult(success: true, path: _rel(abs), bytesWritten: 0, message: 'Удалено: ${_rel(abs)}');
      }
    } on FileSystemException catch (e) {
      return FileOpResult(success: false, path: path, bytesWritten: 0, message: 'Ошибка доступа: ${e.message} (${e.path ?? ''})');
    } catch (e) {
      return FileOpResult(success: false, path: path, bytesWritten: 0, message: 'Ошибка удаления: $e');
    }
  }

  String _rel(String abs) {
    final rr = p.normalize(p.absolute(rootDir));
    final ap = p.normalize(p.absolute(abs));
    return p.relative(ap, from: rr);
  }
}
