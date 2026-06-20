import 'dart:typed_data';

import 'package:arken/src/vault/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultCrypto', () {
    test('derives the same key for the same password and salt', () async {
      final params = KdfParams.defaults();
      final key1 = await VaultCrypto.deriveKey('correct horse', params);
      final key2 = await VaultCrypto.deriveKey('correct horse', params);
      expect(await key1.extractBytes(), await key2.extractBytes());
    });

    test('derives different keys for different passwords', () async {
      final params = KdfParams.defaults();
      final key1 = await VaultCrypto.deriveKey('password one', params);
      final key2 = await VaultCrypto.deriveKey('password two', params);
      expect(await key1.extractBytes(), isNot(await key2.extractBytes()));
    });

    test('encrypts and decrypts a round trip', () async {
      final params = KdfParams.defaults();
      final key = await VaultCrypto.deriveKey('master password', params);
      final plain = Uint8List.fromList('hello, vault'.codeUnits);

      final sealed = await VaultCrypto.encrypt(key, plain);
      final packed = sealed.toBytes();
      final unpacked = SealedBytes.fromBytes(packed);
      final decrypted = await VaultCrypto.decrypt(key, unpacked);

      expect(String.fromCharCodes(decrypted), 'hello, vault');
    });

    test('fails to decrypt with the wrong key', () async {
      final params = KdfParams.defaults();
      final rightKey = await VaultCrypto.deriveKey('right', params);
      final wrongKey = await VaultCrypto.deriveKey('wrong', params);
      final plain = Uint8List.fromList('secret'.codeUnits);

      final sealed = await VaultCrypto.encrypt(rightKey, plain);
      expect(
        () => VaultCrypto.decrypt(wrongKey, sealed),
        throwsA(anything),
      );
    });

    test('checksum is stable and content-addressed', () async {
      final a = Uint8List.fromList('same content'.codeUnits);
      final b = Uint8List.fromList('same content'.codeUnits);
      final c = Uint8List.fromList('different content'.codeUnits);
      expect(await VaultCrypto.checksumOf(a), await VaultCrypto.checksumOf(b));
      expect(await VaultCrypto.checksumOf(a), isNot(await VaultCrypto.checksumOf(c)));
    });
  });
}
