// The open vault session: create/open/lock/save, and the minimal data-layer
// operations needed for Iteration 1 (PRD §12 "create a vault, add a file
// from disk, see it in a list, lock and reopen it").
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'blob_store.dart';
import 'crypto.dart';
import 'models.dart';
import 'vault_format.dart';
import 'vault_index.dart';

class Vault {
  final Directory directory;
  final VaultHeader header;
  final VaultIndex index;
  final BlobStore blobStore;

  /// Held only in memory while unlocked; cleared on [lock] (§7.1).
  SecretKey? _key;

  Vault._({
    required this.directory,
    required this.header,
    required this.index,
    required SecretKey key,
  })  : blobStore = BlobStore(directory),
        _key = key;

  bool get isLocked => _key == null;

  SecretKey get _requireKey {
    final key = _key;
    if (key == null) {
      throw StateError('Vault is locked.');
    }
    return key;
  }

  File get _headerFile => File(p.join(directory.path, headerFileName));
  File get _indexFile => File(p.join(directory.path, indexFileName));

  /// Creates a brand-new vault package at [directoryPath] (§6.1).
  static Future<Vault> create({
    required String directoryPath,
    required String masterPassword,
  }) async {
    final dir = Directory(directoryPath);
    if (await dir.exists() && (await dir.list().toList()).isNotEmpty) {
      throw VaultFormatException('Directory is not empty: $directoryPath');
    }
    await dir.create(recursive: true);

    final kdf = KdfParams.defaults();
    final header = VaultHeader(kdf: kdf);
    final key = await VaultCrypto.deriveKey(masterPassword, kdf);

    final vault = Vault._(
      directory: dir,
      header: header,
      index: VaultIndex.empty(),
      key: key,
    );
    await vault.blobStore.ensureCreated();
    await vault.save();
    return vault;
  }

  /// Opens an existing vault package, deriving the key from [masterPassword]
  /// and verifying it via the index's AEAD tag (§6.5 integrity-on-open).
  static Future<Vault> open({
    required String directoryPath,
    required String masterPassword,
  }) async {
    final dir = Directory(directoryPath);
    final headerFile = File(p.join(dir.path, headerFileName));
    final indexFile = File(p.join(dir.path, indexFileName));
    if (!await headerFile.exists() || !await indexFile.exists()) {
      throw VaultFormatException('Not a valid Arken vault: $directoryPath');
    }

    final header = VaultHeader.decodeJson(await headerFile.readAsString());
    final key = await VaultCrypto.deriveKey(masterPassword, header.kdf);

    VaultIndex index;
    try {
      final sealed = SealedBytes.fromBytes(await indexFile.readAsBytes());
      final plain = await VaultCrypto.decrypt(key, sealed);
      index = VaultIndex.decodeJson(String.fromCharCodes(plain));
    } catch (_) {
      throw VaultAuthenticationException(
        'Could not unlock vault: wrong master password, or the vault is corrupt.',
      );
    }

    return Vault._(directory: dir, header: header, index: index, key: key);
  }

  /// Persists the header and re-encrypts the index (§7.5 atomic saves: write
  /// to a temp file then rename, so an interrupted write can't corrupt the
  /// vault).
  Future<void> save() async {
    header.modifiedAt = DateTime.now().toUtc();
    await _writeAtomic(_headerFile, header.encodeJson().codeUnits);

    final sealed = await VaultCrypto.encrypt(
      _requireKey,
      Uint8List.fromList(index.encodeJson().codeUnits),
    );
    await _writeAtomic(_indexFile, sealed.toBytes());
  }

  Future<void> _writeAtomic(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  }

  /// Clears the in-memory key (§7.1 "sensitive data cleared from memory ...
  /// on lock/exit"). The Vault instance must be reopened afterwards.
  void lock() {
    _key = null;
  }

  /// Imports a file from local disk into the vault (§6.2), encrypting it
  /// into the blob store and creating an Entry for it.
  Future<Entry> addFile(
    String sourcePath, {
    required String folderId,
    String? title,
    List<String> tagIds = const [],
    String category = '',
  }) async {
    final file = File(sourcePath);
    final bytes = await file.readAsBytes();
    final checksum = await blobStore.store(bytes, _requireKey);

    final entry = Entry(
      title: title ?? p.basenameWithoutExtension(sourcePath),
      folderId: folderId,
      category: category,
      fileName: p.basename(sourcePath),
      mimeType: _guessMimeType(sourcePath),
      fileSize: bytes.length,
      checksum: checksum,
      tagIds: tagIds,
    );
    index.addEntry(entry);
    return entry;
  }

  /// Decrypts and returns the bytes of an entry's document (§6.4 open/export).
  Future<Uint8List> readEntryBytes(Entry entry) =>
      blobStore.retrieve(entry.checksum, _requireKey);

  static String _guessMimeType(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.tif':
      case '.tiff':
        return 'image/tiff';
      default:
        return 'application/octet-stream';
    }
  }
}
