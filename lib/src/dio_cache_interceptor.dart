import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/src/model/cache_control.dart';

import './model/cache_response.dart';
import './store/cache_store.dart';
import 'content_serialization.dart';
import 'model/cache_options.dart';
import 'store/db_cache_store.dart';

/// Cache interceptor
class DioCacheInterceptor extends Interceptor {
  static const String _getMethodName = 'GET';

  final CacheOptions _options;
  final CacheStore _store;

  DioCacheInterceptor({required CacheOptions options})
      : _options = options,
        _store = options.store ?? DbCacheStore();

  @override
  Future<dynamic> onRequest(RequestOptions request) async {
    if (_shouldSkipRequest(request.method!)) {
      return super.onRequest(request);
    }

    final options = _getCacheOptions(request);

    if (options.policy == CachePolicy.refresh) {
      return super.onRequest(request);
    }

    final cacheResp = await _getCacheResponse(request);
    if (_shouldReturnCache(options, cacheResp!)) {
      return cacheResp.toResponse(request);
    }

    // Update request with cache directives
    _addCacheDirectives(request, cacheResp);

    return super.onRequest(request);
  }

  @override
  Future<dynamic> onResponse(Response response) async {
    if (_shouldSkipRequest(response.request!.method!)) {
      return super.onResponse(response);
    }

    // Don't cache response
    if (response.statusCode != HttpStatus.ok) {
      return super.onResponse(response);
    }

    final cacheOptions = _getCacheOptions(response.request!);
    if (cacheOptions.policy == CachePolicy.cacheStoreNo) {
      return super.onResponse(response);
    }

    // Cache response into store
    if (cacheOptions.policy == CachePolicy.cacheStoreForce ||
        _hasCacheDirectives(response)) {
      final cacheResp = await _buildCacheResponse(
        cacheOptions.keyBuilder(response.request!),
        cacheOptions,
        response,
      );

      await _getCacheStore(cacheOptions).set(cacheResp);
    }

    return super.onResponse(response);
  }

  @override
  Future<dynamic> onError(DioError err) async {
    if (err.type == DioErrorType.CANCEL ||
        _shouldSkipRequest(err.request!.method!)) {
      return super.onError(err);
    }

    // Retrieve response from cache
    if (err.response!.statusCode == HttpStatus.notModified) {
      return _getResponse(err.request!);
    }

    final cacheOpts = _getCacheOptions(err.request!);

    // Check if we can return cache on error
    if (err.type == DioErrorType.RESPONSE) {
      if (cacheOpts.hitCacheOnErrorExcept!.contains(err.response!.statusCode)) {
        return super.onError(err);
      }
    }

    return _getResponse(err.request!);
  }

  void _addCacheDirectives(RequestOptions request, CacheResponse response) {
    request.headers[HttpHeaders.ifNoneMatchHeader] = response.eTag;
    request.headers[HttpHeaders.ifModifiedSinceHeader] = response.lastModified;
  }

  bool _hasCacheDirectives(Response response) {
    var result = response.headers[HttpHeaders.etagHeader] != null;
    result |= response.headers[HttpHeaders.lastModifiedHeader] != null;

    final cacheControl = CacheControl.fromHeader(
      response.headers[HttpHeaders.cacheControlHeader]!,
    );

    result &= !(cacheControl.noStore);

    return result;
  }

  bool _shouldReturnCache(CacheOptions options, CacheResponse cacheResp) {
    // Forced cache response
    if (options.policy == CachePolicy.cacheStoreForce) {
      return true;
    }

    // Cache first requested, check max age, expires, etc.
    if (options.policy == CachePolicy.cacheFirst) {
      return !(cacheResp.cacheControl.isStale(
        cacheResp.responseDate,
        cacheResp.date,
        cacheResp.expires,
      ));
    }

    return false;
  }

  CacheOptions _getCacheOptions(RequestOptions request) {
    return CacheOptions.fromExtra(request);
  }

  CacheStore _getCacheStore(CacheOptions options) {
    return options.store ?? _store;
  }

  bool _shouldSkipRequest(String method) {
    return (method.toUpperCase() != _getMethodName);
  }

  Future<CacheResponse> _buildCacheResponse(
    String key,
    CacheOptions options,
    Response response,
  ) async {
    final content = await _encryptContent(
      options,
      await serializeContent(response.request!.responseType!, response.data),
    );

    final headers = await _encryptContent(
      options,
      utf8.encode(jsonEncode(response.headers.map)),
    );

    final httpDate = response.headers[HttpHeaders.dateHeader]?.first;
    final date =
        (httpDate != null) ? HttpDate.parse(httpDate) : DateTime.now().toUtc();

    final httpExpiresDate = response.headers[HttpHeaders.expiresHeader]?.first;
    var expiresDate;
    if (httpExpiresDate != null) {
      try {
        expiresDate = HttpDate.parse(httpDate!);
      } catch (_) {
        // Invalid date format, meaning something already expired
        expiresDate = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
      }
    }

    return CacheResponse(
      cacheControl: CacheControl.fromHeader(
        response.headers[HttpHeaders.cacheControlHeader]!,
      ),
      content: content,
      date: date,
      eTag: response.headers[HttpHeaders.etagHeader] != null
          ? response.headers[HttpHeaders.etagHeader]!.first
          : '',
      expires: expiresDate,
      headers: headers,
      key: key,
      lastModified: response.headers[HttpHeaders.lastModifiedHeader] != null
          ? response.headers[HttpHeaders.lastModifiedHeader]!.first
          : '',
      maxStale: options.maxStale != null
          ? DateTime.now().toUtc().add(options.maxStale!)
          : DateTime.now(),
      priority: options.priority,
      responseDate: DateTime.now().toUtc(),
      url: response.request!.uri.toString(),
    );
  }

  Future<CacheResponse?> _getCacheResponse(RequestOptions request) async {
    final cacheOpts = _getCacheOptions(request);
    final cacheKey = cacheOpts.keyBuilder(request);
    final result = await _getCacheStore(cacheOpts).get(cacheKey);

    if (result != null) {
      result.content = await _decryptContent(cacheOpts, result.content);
      result.headers = await _decryptContent(cacheOpts, result.headers);
    }

    return result;
  }

  Future<Response?> _getResponse(RequestOptions request) async {
    final existing = await _getCacheResponse(request);
    return existing!.toResponse(request);
  }

  Future<List<int>> _decryptContent(CacheOptions options, List<int> bytes) {
    return options.cipher!.decrypt(bytes);
  }

  Future<List<int>> _encryptContent(CacheOptions options, List<int> bytes) {
    return options.cipher!.encrypt(bytes);
  }
}
