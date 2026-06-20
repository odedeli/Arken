// Versioned vault package format (PRD §10.2). A vault is a directory:
//
//   <vault>/
//     header.json   -- plaintext: format version, KDF + cipher params
//     index.enc      -- AEAD-sealed VaultIndex (folders/tags/entries/fields)
//     blobs/<sha256> -- AEAD-sealed document blobs, content-addressed
//
// Pre-1.0 builds use a 0.x format version and may change between releases;
// the format freezes at 1.0 (PRD §2.3).
import 'dart:convert';

import 'crypto.dart';

const vaultFormatVersion = '0.1';
const headerFileName = 'header.json';
const indexFileName = 'index.enc';
const blobsDirName = 'blobs';

class VaultHeader {
  final String formatVersion;
  final KdfParams kdf;
  final String cipherAlgorithm;
  final String kdfAlgorithm;
  final DateTime createdAt;
  DateTime modifiedAt;

  VaultHeader({
    this.formatVersion = vaultFormatVersion,
    required this.kdf,
    this.cipherAlgorithm = VaultCrypto.algorithmId,
    this.kdfAlgorithm = VaultCrypto.kdfId,
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        modifiedAt = modifiedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'kdfAlgorithm': kdfAlgorithm,
        'kdf': kdf.toJson(),
        'cipherAlgorithm': cipherAlgorithm,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory VaultHeader.fromJson(Map<String, dynamic> json) => VaultHeader(
        formatVersion: json['formatVersion'] as String,
        kdfAlgorithm: json['kdfAlgorithm'] as String,
        kdf: KdfParams.fromJson(json['kdf'] as Map<String, dynamic>),
        cipherAlgorithm: json['cipherAlgorithm'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );

  String encodeJson() => jsonEncode(toJson());

  factory VaultHeader.decodeJson(String source) =>
      VaultHeader.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

/// Thrown when a vault's master password / key file is wrong, or the vault
/// is corrupt, on open (PRD §6.5 "verify vault integrity on open").
class VaultAuthenticationException implements Exception {
  final String message;
  VaultAuthenticationException(this.message);
  @override
  String toString() => 'VaultAuthenticationException: $message';
}

/// Thrown when a vault directory doesn't look like a valid vault package.
class VaultFormatException implements Exception {
  final String message;
  VaultFormatException(this.message);
  @override
  String toString() => 'VaultFormatException: $message';
}
