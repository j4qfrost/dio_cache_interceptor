import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio_cache_interceptor/src/model/cache_control.dart';
import 'package:path/path.dart' as path;

import '../model/cache_priority.dart';
import '../model/cache_response.dart';
import 'cache_store.dart';

/// A store saving responses in a dedicated file from a given root [directory].
///
class FileCacheStore extends CacheStore {
  final Map<CachePriority, Directory> _directories;

  FileCacheStore(Directory directory)
      : _directories = _genDirectories(directory) {
    clean(staleOnly: true);
  }

  File? _findFile(String key) {
    for (final entry in _directories.entries) {
      final file = File(path.join(entry.value.path, key));
      if (file.existsSync()) {
        return file;
      }
    }

    return null;
  }

  @override
  Future<List> clean({
    CachePriority priorityOrBelow = CachePriority.high,
    bool staleOnly = false,
  }) async {
    final futures = Iterable.generate(priorityOrBelow.index + 1, (i) async {
      final directory = _directories[CachePriority.values[i]]!;

      if (directory.existsSync()) return;

      if (staleOnly) {
        directory.listSync().forEach((file) async {
          await deleteFile(file as File, staleOnly: staleOnly);
        });
      }

      if (!staleOnly || directory.listSync().isEmpty) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
    });

    return Future.wait(futures);
  }

  @override
  Future<void> delete(String key, {bool staleOnly = false}) async {
    // TODO: add try catch
    final file = _findFile(key);
    if (file != null && file.existsSync()) {
      return deleteFile(_findFile(key)!, staleOnly: staleOnly);
    }
    return Future.value();
  }

  @override
  Future<bool> exists(String key) {
    return Future.value(_findFile(key) != null);
  }

  @override
  Future<CacheResponse?> get(String key) async {
    final file = _findFile(key);
    if (file == null) {
      // TODO: improve miss reporting
      print('Cache miss!');
      return Future.value();
    }

    final resp = await _deserializeContent(file);

    // Purge entry if stalled
    final maxStale = resp.maxStale;
    if (DateTime.now().toUtc().isAfter(maxStale)) {
      await delete(key);
      return null;
    }

    return resp;
  }

  @override
  Future<void> set(CacheResponse response) async {
    await delete(response.key);

    final file = File(
      path.join(
        _directories[response.priority]!.path,
        response.key,
      ),
    );

    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }

    final bytes = _serializeContent(response);
    await file.writeAsBytes(bytes, flush: true);
  }

  List<int> _serializeContent(CacheResponse response) {
    final etag = utf8.encode(response.eTag);
    final lastModified = utf8.encode(response.lastModified);
    final maxStale = utf8.encode(response.getMaxStaleSeconds().toString());
    final url = utf8.encode(response.url);
    final cacheControl = utf8.encode(response.cacheControl.toHeader());
    final date = utf8.encode(response.date.toIso8601String());
    final expires = utf8.encode(response.expires.toIso8601String());
    final responseDate = utf8.encode(response.responseDate.toIso8601String());

    return [
      ...Int32List.fromList([
        response.content.length,
        etag.length,
        response.headers.length,
        lastModified.length,
        maxStale.length,
        url.length,
        cacheControl.length,
        date.length,
        expires.length,
        responseDate.length,
      ]).buffer.asInt8List(),
      ...response.content,
      ...etag,
      ...response.headers,
      ...lastModified,
      ...maxStale,
      ...url,
      ...cacheControl,
      ...date,
      ...expires,
      ...responseDate,
    ];
  }

  Future<CacheResponse> _deserializeContent(File file) async {
    final data = await file.readAsBytes();

    // Get field sizes
    // 10 fields. int is encoded with 32 bits (4 bytes)
    var i = 10 * 4;
    final sizes = Int8List.fromList(
      data.take(i).toList(),
    ).buffer.asInt32List();

    var fieldIndex = 0;

    var size = sizes[fieldIndex++];
    final content =
        size != 0 ? data.skip(i).take(size).toList() : [] as List<int>;

    i += size;
    size = sizes[fieldIndex++];
    final etag = size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    i += size;
    size = sizes[fieldIndex++];
    final headers =
        size != 0 ? data.skip(i).take(size).toList() : [] as List<int>;

    i += size;
    size = sizes[fieldIndex++];
    final lastModified =
        size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    i += size;
    size = sizes[fieldIndex++];
    final maxStale =
        size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : null;

    i += size;
    size = sizes[fieldIndex++];
    final url = size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    i += size;
    size = sizes[fieldIndex++];
    final cacheControl =
        size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    i += size;
    size = sizes[fieldIndex++];
    final date = size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    i += size;
    size = sizes[fieldIndex++];
    final expires =
        size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    i += size;
    size = sizes[fieldIndex++];
    final responseDate =
        size != 0 ? utf8.decode(data.skip(i).take(size).toList()) : '';

    return CacheResponse(
      cacheControl: CacheControl.fromHeader(cacheControl.split(', ')),
      content: content,
      date: DateTime.tryParse(date) ?? DateTime.now(),
      eTag: etag,
      expires: DateTime.tryParse(expires) ?? DateTime.now(),
      headers: headers,
      key: path.basename(file.path),
      lastModified: lastModified,
      maxStale: maxStale != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(maxStale) ?? DateTime.now().millisecond,
              isUtc: true)
          : DateTime.now(),
      priority: _getPriority(file),
      responseDate: DateTime.tryParse(responseDate) ?? DateTime.now(),
      url: url,
    );
  }

  CachePriority _getPriority(File file) {
    final priority = path.basename(file.parent.path);

    if (priority == CachePriority.low.toShortString()) {
      return CachePriority.low;
    } else if (priority == CachePriority.normal.toShortString()) {
      return CachePriority.normal;
    }

    return CachePriority.high;
  }

  Future<void> deleteFile(
    File file, {
    bool staleOnly = false,
  }) async {
    if (file.existsSync()) {
      if (staleOnly) {
        final resp = await _deserializeContent(file);
        if (DateTime.now().toUtc().isBefore(resp.maxStale)) {
          return Future.value();
        }
      }

      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

Map<CachePriority, Directory> _genDirectories(Directory directory) {
  return Map.fromEntries(
    Iterable.generate(
      CachePriority.values.length,
      (i) {
        final priority = CachePriority.values[i];
        final subDir = Directory(
          path.join(directory.path, priority.toShortString()),
        );

        return MapEntry(priority, subDir);
      },
    ),
  );
}
