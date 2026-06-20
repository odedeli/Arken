import 'dart:io';

import 'package:arken/src/vault/vault.dart';
import 'package:arken/src/vault/vault_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('arken_vault_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('create -> save -> open round trip preserves folders and entries', () async {
    final vaultPath = p.join(tmp.path, 'my.arken');
    final vault = await Vault.create(
      directoryPath: vaultPath,
      masterPassword: 's3cret!',
    );
    final folder = vault.index.addFolder('Finance');
    await vault.save();
    vault.lock();
    expect(vault.isLocked, isTrue);

    // Add a source file to import.
    final sourceFile = File(p.join(tmp.path, 'statement.pdf'));
    await sourceFile.writeAsBytes(List<int>.filled(1024, 7));

    final reopened = await Vault.open(
      directoryPath: vaultPath,
      masterPassword: 's3cret!',
    );
    expect(reopened.index.folders.map((f) => f.name), contains('Finance'));

    final entry = await reopened.addFile(
      sourceFile.path,
      folderId: folder.id,
      title: 'Statement',
    );
    await reopened.save();

    final bytes = await reopened.readEntryBytes(entry);
    expect(bytes.length, 1024);

    final reopenedAgain = await Vault.open(
      directoryPath: vaultPath,
      masterPassword: 's3cret!',
    );
    expect(reopenedAgain.index.entries.length, 1);
    expect(reopenedAgain.index.entries.first.title, 'Statement');
  });

  test('opening with the wrong master password throws', () async {
    final vaultPath = p.join(tmp.path, 'my.arken');
    await Vault.create(directoryPath: vaultPath, masterPassword: 'right-password');

    expect(
      () => Vault.open(directoryPath: vaultPath, masterPassword: 'wrong-password'),
      throwsA(isA<VaultAuthenticationException>()),
    );
  });

  test('opening a non-vault directory throws VaultFormatException', () async {
    expect(
      () => Vault.open(directoryPath: tmp.path, masterPassword: 'x'),
      throwsA(isA<VaultFormatException>()),
    );
  });

  test('importing the same file twice deduplicates the blob', () async {
    final vaultPath = p.join(tmp.path, 'my.arken');
    final vault = await Vault.create(directoryPath: vaultPath, masterPassword: 'pw');
    final folder = vault.index.addFolder('Docs');

    final sourceFile = File(p.join(tmp.path, 'dup.pdf'));
    await sourceFile.writeAsBytes(List<int>.filled(512, 3));

    final e1 = await vault.addFile(sourceFile.path, folderId: folder.id);
    final e2 = await vault.addFile(sourceFile.path, folderId: folder.id);
    expect(e1.checksum, e2.checksum);

    final blobFiles = await Directory(p.join(vaultPath, 'blobs')).list().toList();
    expect(blobFiles.length, 1);
  });
}
