import 'package:arken/src/vault/models.dart';
import 'package:arken/src/vault/vault_index.dart';
import 'package:flutter_test/flutter_test.dart';

VaultIndex _withEntry(VaultIndex index, Folder folder, {List<String> tagIds = const []}) {
  index.addEntry(Entry(
    title: 'Doc',
    folderId: folder.id,
    fileName: 'doc.pdf',
    mimeType: 'application/pdf',
    fileSize: 10,
    checksum: 'abc',
    tagIds: List<String>.from(tagIds),
  ));
  return index;
}

void main() {
  group('VaultIndex folder management', () {
    test('renameFolder updates the name in place', () {
      final index = VaultIndex.empty();
      final folder = index.addFolder('Finance');
      index.renameFolder(folder.id, 'Money');
      expect(index.folderById(folder.id)!.name, 'Money');
    });

    test('renameFolder throws for an unknown id', () {
      final index = VaultIndex.empty();
      expect(() => index.renameFolder('missing', 'x'), throwsArgumentError);
    });

    test('deleteFolder promotes subfolders and entries to the parent', () {
      final index = VaultIndex.empty();
      final root = index.addFolder('Home');
      final child = index.addFolder('Bills', parentId: root.id);
      final grandchild = index.addFolder('Utilities', parentId: child.id);
      _withEntry(index, child);

      index.deleteFolder(child.id);

      expect(index.folders.any((f) => f.id == child.id), isFalse);
      expect(index.folderById(grandchild.id)!.parentId, root.id);
      expect(index.entries.single.folderId, root.id);
    });

    test('deleteFolder honours an explicit destination', () {
      final index = VaultIndex.empty();
      final a = index.addFolder('A');
      final b = index.addFolder('B');
      _withEntry(index, a);

      index.deleteFolder(a.id, moveContentsTo: b.id);

      expect(index.entries.single.folderId, b.id);
    });

    test('deleteFolder throws when entries have nowhere to go', () {
      final index = VaultIndex.empty();
      final root = index.addFolder('Home');
      _withEntry(index, root);

      expect(() => index.deleteFolder(root.id), throwsStateError);
    });

    test('moveEntry updates folderId and modifiedDate', () {
      final index = VaultIndex.empty();
      final a = index.addFolder('A');
      final b = index.addFolder('B');
      _withEntry(index, a);
      final entry = index.entries.single;
      final before = entry.modifiedDate;

      index.moveEntry(entry.id, b.id);

      expect(entry.folderId, b.id);
      expect(entry.modifiedDate.isAtSameMomentAs(before) || entry.modifiedDate.isAfter(before), isTrue);
    });
  });

  group('VaultIndex tag management', () {
    test('renameTag updates the name in place', () {
      final index = VaultIndex.empty();
      final tag = index.addTag('Urgent');
      index.renameTag(tag.id, 'Important');
      expect(index.tagById(tag.id)!.name, 'Important');
    });

    test('deleteTag removes it from the vault and from entries', () {
      final index = VaultIndex.empty();
      final folder = index.addFolder('Home');
      final tag = index.addTag('Urgent');
      _withEntry(index, folder, tagIds: [tag.id]);

      index.deleteTag(tag.id);

      expect(index.tags, isEmpty);
      expect(index.entries.single.tagIds, isEmpty);
    });

    test('mergeTags folds source tags into the target without duplicating', () {
      final index = VaultIndex.empty();
      final folder = index.addFolder('Home');
      final urgent = index.addTag('Urgent');
      final asap = index.addTag('ASAP');
      final important = index.addTag('Important');
      _withEntry(index, folder, tagIds: [urgent.id, important.id]);
      index.addEntry(Entry(
        title: 'Doc2',
        folderId: folder.id,
        fileName: 'doc2.pdf',
        mimeType: 'application/pdf',
        fileSize: 5,
        checksum: 'def',
        tagIds: [asap.id],
      ));

      index.mergeTags([urgent.id, asap.id], important.id);

      expect(index.tags.map((t) => t.id), [important.id]);
      expect(index.entries[0].tagIds, [important.id]);
      expect(index.entries[1].tagIds, [important.id]);
    });

    test('addTagToEntry and removeTagFromEntry mutate tagIds', () {
      final index = VaultIndex.empty();
      final folder = index.addFolder('Home');
      final tag = index.addTag('Urgent');
      _withEntry(index, folder);
      final entry = index.entries.single;

      index.addTagToEntry(entry.id, tag.id);
      expect(entry.tagIds, [tag.id]);

      index.addTagToEntry(entry.id, tag.id);
      expect(entry.tagIds, [tag.id]);

      index.removeTagFromEntry(entry.id, tag.id);
      expect(entry.tagIds, isEmpty);
    });
  });
}
