import 'dart:convert' show jsonDecode, utf8;

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/src/model/cache_control.dart';
import 'package:moor/moor.dart';

import '../util/content_serialization.dart';
import 'cache_priority.dart';

/// Response representation from cache store.
class CacheResponse {
  /// Cache key available in [Response]
  static const String cacheKey = '@cache_key@';

  /// Available in [Response] if coming from this object.
  static const String fromCache = '@fromCache@';

  /// Response Cache-control header
  final CacheControl cacheControl;

  /// Response body
  Uint8List? content;

  /// Response Date header
  final DateTime? date;

  /// ETag header
  final String? eTag;

  /// Expires header
  final DateTime? expires;

  /// Response headers
  Uint8List? headers;

  /// Key used by store
  final String key;

  /// Last-modified header
  final DateTime lastModified;

  /// Max stale expiry
  final DateTime? maxStale;

  /// Cache priority
  final CachePriority priority;

  /// Absolute date representing date/time when response has been received
  final DateTime responseDate;

  /// Initial request URL
  final String url;

  CacheResponse({
    required this.cacheControl,
    this.content,
    this.date,
    this.eTag,
    this.expires,
    this.headers,
    required this.key,
    required this.lastModified,
    this.maxStale,
    this.priority = CachePriority.normal,
    required this.responseDate,
    required this.url,
  });

  /// Returns date in seconds since epoch or null.
  int getMaxStaleSeconds() {
    return maxStale != null ? maxStale!.millisecondsSinceEpoch ~/ 1000 : 0;
  }

  Response toResponse(RequestOptions options) {
    final decHeaders =
        jsonDecode(utf8.decode(headers ?? [])) as Map<String, dynamic>;

    final h = Headers();
    decHeaders.forEach((key, value) => h.set(key, value));

    return Response(
      data: deserializeContent(options.responseType!, content ?? []),
      extra: {cacheKey: key, fromCache: true},
      headers: h,
      statusCode: 304,
      request: options,
    );
  }
}
