import 'dart:io';

import 'package:arken/src/ui/library_view.dart';
import 'package:arken/src/vault/vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late Vault vault;

  Future<Vault> createVault(Directory dir) => Vault.create(
        directoryPath: p.join(dir.path, 'vault'),
        masterPassword: 'correct horse battery staple',
      );

  testWidgets('renders folders, tags and entries, and supports search', (tester) async {
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('arken_library_view_test');
      vault = await createVault(tempDir);
      final folder = vault.index.addFolder('Finance');
      vault.index.addTag('Urgent');
      final sourceFile = File(p.join(tempDir.path, 'bill.pdf'));
      await sourceFile.writeAsBytes([1, 2, 3]);
      await vault.addFile(sourceFile.path, folderId: folder.id, title: 'Electricity bill');
      await vault.save();
    });
    addTearDown(() => tempDir.deleteSync(recursive: true));

    await tester.pumpWidget(MaterialApp(
      home: LibraryView(
        vault: vault,
        busy: false,
        topError: null,
        onImportFile: () {},
        onCaptureFile: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Electricity bill'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'nomatch');
    await tester.pumpAndSettle();
    expect(find.text('Electricity bill'), findsNothing);
  });
}
