import 'dart:convert';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:moor/moor.dart' as moor;
import 'package:test/test.dart';

void testGroup(String description, CacheStore store) {
  group(description, () {
    Future<void> _addFooResponse() {
      final resp = CacheResponse(
        cacheControl: CacheControl(),
        content: utf8.encode('foo') as moor.Uint8List,
        date: DateTime.now().toUtc(),
        eTag: 'an etag',
        expires: DateTime.now().toUtc().add(Duration(minutes: 10)),
        key: 'foo',
        maxStale: DateTime.now().toUtc().add(Duration(minutes: 10)),
        responseDate: DateTime.now().toUtc().add(Duration(seconds: 5)),
        url: 'https://foo.com',
        lastModified: DateTime.now().toUtc(),
      );

      return store.set(resp);
    }

    test('Empty by default', () async {
      expect(await store.exists('foo'), isFalse);
    });

    test('Add item', () async {
      await _addFooResponse();

      expect(await store.exists('foo'), isTrue);
    });

    test('Get item', () async {
      await _addFooResponse();

      final resp = await store.get('foo');
      expect(resp, isNotNull);
      expect(resp!.key, 'foo');
      expect(resp.url, 'https://foo.com');
      expect(resp.eTag, 'an etag');
      // expect(resp.lastModified, isNull);
      // expect(resp.maxStale, isNull);
      expect(resp.content, utf8.encode('foo'));
      // expect(resp.headers, isNull);
      expect(resp.priority, CachePriority.normal);
    });

    test('Delete item', () async {
      await _addFooResponse();
      expect(await store.exists('foo'), isTrue);

      await store.delete('foo');
      expect(await store.exists('foo'), isFalse);
    });
  });
}
