import 'package:moor/moor.dart';

abstract class Cipher {
  Future<Uint8List> encrypt(List<int> bytes);
  Future<Uint8List> decrypt(List<int> bytes);
}
