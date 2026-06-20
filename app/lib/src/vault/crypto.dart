// Vault cryptography primitives: Argon2id key derivation and authenticated
// encryption (ChaCha20-Poly1305). See PRD §7.1 / §10.2.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Argon2id parameters used to derive the vault's encryption key from the
/// master password. Persisted (unencrypted) in the vault header so the same
/// key can be re-derived on open.
class KdfParams {
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;

  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
  });

  /// Sensible interactive defaults; tune per §7.1 "configurable cost".
  factory KdfParams.defaults({Uint8List? salt}) => KdfParams(
        memoryKiB: 64 * 1024, // 64 MiB
        iterations: 3,
        parallelism: 4,
        salt: salt ?? randomSalt(),
      );

  static Uint8List randomSalt([int length = 16]) {
    final rand = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rand.nextInt(256)),
    );
  }

  Map<String, dynamic> toJson() => {
        'memoryKiB': memoryKiB,
        'iterations': iterations,
        'parallelism': parallelism,
        'salt': base64Encode(salt),
      };

  factory KdfParams.fromJson(Map<String, dynamic> json) => KdfParams(
        memoryKiB: json['memoryKiB'] as int,
        iterations: json['iterations'] as int,
        parallelism: json['parallelism'] as int,
        salt: base64Decode(json['salt'] as String),
      );
}

/// A packed authenticated-encryption payload: nonce || ciphertext || mac,
/// base64-friendly for embedding in JSON headers when needed.
class SealedBytes {
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  const SealedBytes({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  /// Concatenated wire format written to disk: [nonceLen][nonce][mac(16)][cipherText]
  Uint8List toBytes() {
    final out = BytesBuilder();
    out.addByte(nonce.length);
    out.add(nonce);
    out.add(mac);
    out.add(cipherText);
    return out.toBytes();
  }

  static SealedBytes fromBytes(Uint8List bytes) {
    final nonceLen = bytes[0];
    final nonce = bytes.sublist(1, 1 + nonceLen);
    final mac = bytes.sublist(1 + nonceLen, 1 + nonceLen + 16);
    final cipherText = bytes.sublist(1 + nonceLen + 16);
    return SealedBytes(nonce: nonce, cipherText: cipherText, mac: mac);
  }
}

/// Derives keys and performs authenticated encryption/decryption for the
/// vault. Algorithm choices per PRD §7.1 / §10.1: Argon2id KDF,
/// ChaCha20-Poly1305 AEAD.
class VaultCrypto {
  static final _aead = Chacha20.poly1305Aead();
  static const algorithmId = 'chacha20-poly1305';
  static const kdfId = 'argon2id';

  /// Derives a 32-byte secret key from [password] using Argon2id.
  static Future<SecretKey> deriveKey(String password, KdfParams params) async {
    final argon2id = Argon2id(
      memory: params.memoryKiB,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: 32,
    );
    return argon2id.deriveKeyFromPassword(
      password: password,
      nonce: params.salt,
    );
  }

  static Future<SealedBytes> encrypt(SecretKey key, Uint8List plainText) async {
    final secretBox = await _aead.encrypt(plainText, secretKey: key);
    return SealedBytes(
      nonce: Uint8List.fromList(secretBox.nonce),
      cipherText: Uint8List.fromList(secretBox.cipherText),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  static Future<Uint8List> decrypt(SecretKey key, SealedBytes sealed) async {
    final secretBox = SecretBox(
      sealed.cipherText,
      nonce: sealed.nonce,
      mac: Mac(sealed.mac),
    );
    final clear = await _aead.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(clear);
  }

  /// SHA-256 checksum used for content-addressed blob storage (§9.1 FileBlob).
  static Future<String> checksumOf(Uint8List bytes) async {
    final hash = await Sha256().hash(bytes);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
