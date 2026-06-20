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

  group('VaultIndex search & filters', () {
    VaultIndex buildIndex() {
      final index = VaultIndex.empty();
      final folder = index.addFolder('Home');
      final tag = index.addTag('Urgent');
      index.addEntry(Entry(
        title: 'Electricity bill',
        folderId: folder.id,
        fileName: 'elec.pdf',
        mimeType: 'application/pdf',
        fileSize: 10,
        checksum: 'a',
        notes: 'Quarterly invoice',
        documentDate: DateTime.utc(2026, 1, 10),
        tagIds: [tag.id],
      ));
      index.addEntry(Entry(
        title: 'Passport scan',
        folderId: folder.id,
        fileName: 'passport.jpg',
        mimeType: 'image/jpeg',
        fileSize: 5,
        checksum: 'b',
        documentDate: DateTime.utc(2025, 6, 1),
        isFavourite: true,
      ));
      index.addEntry(Entry(
        title: 'Old receipt',
        folderId: folder.id,
        fileName: 'receipt.pdf',
        mimeType: 'application/pdf',
        fileSize: 3,
        checksum: 'c',
        isArchived: true,
      ));
      return index;
    }

    test('search by text matches title and notes, excludes archived by default', () {
      final index = buildIndex();
      final results = index.search(query: 'invoice');
      expect(results.map((e) => e.title), ['Electricity bill']);
    });

    test('search by mimeType filters correctly', () {
      final index = buildIndex();
      final results = index.search(mimeType: 'image/jpeg');
      expect(results.map((e) => e.title), ['Passport scan']);
    });

    test('search by tag requires all listed tags', () {
      final index = buildIndex();
      final tagId = index.tags.single.id;
      final results = index.search(tagIds: [tagId]);
      expect(results.map((e) => e.title), ['Electricity bill']);
    });

    test('search by date range filters on documentDate', () {
      final index = buildIndex();
      final results = index.search(
        dateFrom: DateTime.utc(2026, 1, 1),
        dateTo: DateTime.utc(2026, 12, 31),
      );
      expect(results.map((e) => e.title), ['Electricity bill']);
    });

    test('favouritesOnly returns only favourites and excludes archived', () {
      final index = buildIndex();
      final results = index.search(favouritesOnly: true);
      expect(results.map((e) => e.title), ['Passport scan']);
    });

    test('includeArchived surfaces archived entries', () {
      final index = buildIndex();
      final results = index.search(includeArchived: true);
      expect(results.length, 3);
    });

    test('favourites and archived getters', () {
      final index = buildIndex();
      expect(index.favourites.map((e) => e.title), ['Passport scan']);
      expect(index.archived.map((e) => e.title), ['Old receipt']);
    });

    test('setFavourite and setArchived toggle flags', () {
      final index = buildIndex();
      final entry = index.entries.first;
      index.setFavourite(entry.id, true);
      expect(entry.isFavourite, isTrue);
      index.setArchived(entry.id, true);
      expect(entry.isArchived, isTrue);
    });
  });

  group('FieldDefinition input masks', () {
    test('matches digit, letter and alphanumeric placeholders', () {
      final field = FieldDefinition(
        name: 'SSN',
        type: FieldType.text,
        inputMask: '999-99-9999',
      );
      expect(field.matchesInputMask('123-45-6789'), isTrue);
      expect(field.matchesInputMask('12-345-6789'), isFalse);
    });

    test('no mask always matches', () {
      final field = FieldDefinition(name: 'Note', type: FieldType.text);
      expect(field.matchesInputMask('anything'), isTrue);
    });
  });
}
