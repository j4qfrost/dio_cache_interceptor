import 'dart:io';

import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:path_provider/path_provider.dart';

import './common_store_test.dart' as common;

Future main() async {
  final directory = await getApplicationDocumentsDirectory() ?? Directory('./');
  final store = FileCacheStore(directory);
  common.testGroup('Common File store tests', store);
}
