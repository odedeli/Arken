// Content-addressed, individually encrypted document blob storage
// (PRD §9.1 FileBlob, §10.2). Identical files are stored once, keyed by
// their SHA-256 checksum.
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'crypto.dart';
import 'vault_format.dart';

class BlobStore {
  final Directory blobsDir;

  BlobStore(Directory vaultDir) : blobsDir = Directory(p.join(vaultDir.path, blobsDirName));

  Future<void> ensureCreated() => blobsDir.create(recursive: true);

  File _fileFor(String checksum) => File(p.join(blobsDir.path, '$checksum.enc'));

  /// Encrypts and stores [bytes] under their checksum, skipping the write if
  /// an identical blob already exists (deduplication). Returns the checksum.
  Future<String> store(Uint8List bytes, SecretKey key) async {
    final checksum = await VaultCrypto.checksumOf(bytes);
    final file = _fileFor(checksum);
    if (await file.exists()) return checksum;
    await ensureCreated();
    final sealed = await VaultCrypto.encrypt(key, bytes);
    await file.writeAsBytes(sealed.toBytes(), flush: true);
    return checksum;
  }

  /// Decrypts and returns the blob with the given [checksum].
  Future<Uint8List> retrieve(String checksum, SecretKey key) async {
    final file = _fileFor(checksum);
    if (!await file.exists()) {
      throw VaultFormatException('Missing blob for checksum $checksum');
    }
    final raw = await file.readAsBytes();
    final sealed = SealedBytes.fromBytes(raw);
    return VaultCrypto.decrypt(key, sealed);
  }

  Future<bool> contains(String checksum) => _fileFor(checksum).exists();
}
