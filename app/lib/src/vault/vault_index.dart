// The vault's encrypted index: folders, tags, entries, and custom-field
// definitions/sets (PRD §9.1, §10.2). This is the plaintext-once-decrypted
// JSON document; Vault handles sealing it to/from disk.
import 'dart:convert';

import 'models.dart';

class VaultIndex {
  final List<Folder> folders;
  final List<Tag> tags;
  final List<Entry> entries;
  final List<FieldDefinition> fieldDefinitions;
  final List<FieldSet> fieldSets;

  VaultIndex({
    List<Folder>? folders,
    List<Tag>? tags,
    List<Entry>? entries,
    List<FieldDefinition>? fieldDefinitions,
    List<FieldSet>? fieldSets,
  })  : folders = folders ?? [],
        tags = tags ?? [],
        entries = entries ?? [],
        fieldDefinitions = fieldDefinitions ?? [],
        fieldSets = fieldSets ?? [];

  factory VaultIndex.empty() => VaultIndex();

  Map<String, dynamic> toJson() => {
        'folders': folders.map((f) => f.toJson()).toList(),
        'tags': tags.map((t) => t.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'fieldDefinitions': fieldDefinitions.map((f) => f.toJson()).toList(),
        'fieldSets': fieldSets.map((s) => s.toJson()).toList(),
      };

  factory VaultIndex.fromJson(Map<String, dynamic> json) => VaultIndex(
        folders: (json['folders'] as List? ?? [])
            .map((f) => Folder.fromJson(f as Map<String, dynamic>))
            .toList(),
        tags: (json['tags'] as List? ?? [])
            .map((t) => Tag.fromJson(t as Map<String, dynamic>))
            .toList(),
        entries: (json['entries'] as List? ?? [])
            .map((e) => Entry.fromJson(e as Map<String, dynamic>))
            .toList(),
        fieldDefinitions: (json['fieldDefinitions'] as List? ?? [])
            .map((f) => FieldDefinition.fromJson(f as Map<String, dynamic>))
            .toList(),
        fieldSets: (json['fieldSets'] as List? ?? [])
            .map((s) => FieldSet.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  String encodeJson() => jsonEncode(toJson());

  factory VaultIndex.decodeJson(String source) =>
      VaultIndex.fromJson(jsonDecode(source) as Map<String, dynamic>);

  // --- Convenience mutators (Iteration 1 minimal CRUD; UI lands later) ---

  Folder addFolder(String name, {String? parentId}) {
    final folder = Folder(name: name, parentId: parentId);
    folders.add(folder);
    return folder;
  }

  Tag addTag(String name, {String? colour}) {
    final tag = Tag(name: name, colour: colour);
    tags.add(tag);
    return tag;
  }

  void addEntry(Entry entry) => entries.add(entry);

  Entry? entryById(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  void removeEntry(String id) => entries.removeWhere((e) => e.id == id);

  // --- Folder management (Iteration 2, PRD §6.6 "organise into folders") ---

  Folder? folderById(String id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  void renameFolder(String id, String newName) {
    final folder = folderById(id);
    if (folder == null) {
      throw ArgumentError('No folder with id $id');
    }
    folder.name = newName;
  }

  /// Deletes a folder, reassigning its subfolders and entries to
  /// [moveContentsTo] (defaulting to the deleted folder's own parent, i.e.
  /// "promote contents up one level"). Throws if the folder has entries and
  /// there is nowhere to move them to (e.g. deleting an empty-parent root).
  void deleteFolder(String id, {String? moveContentsTo}) {
    final folder = folderById(id);
    if (folder == null) return;
    final target = moveContentsTo ?? folder.parentId;

    final hasEntries = entries.any((e) => e.folderId == id);
    if (hasEntries && target == null) {
      throw StateError(
        'Cannot delete folder "${folder.name}": it has entries and no '
        'destination folder was given.',
      );
    }

    for (final f in folders.where((f) => f.parentId == id)) {
      f.parentId = target;
    }
    for (final e in entries.where((e) => e.folderId == id)) {
      e.folderId = target!;
      e.modifiedDate = DateTime.now().toUtc();
    }
    folders.removeWhere((f) => f.id == id);
  }

  void moveEntry(String entryId, String folderId) {
    final entry = entryById(entryId);
    if (entry == null) {
      throw ArgumentError('No entry with id $entryId');
    }
    entry.folderId = folderId;
    entry.modifiedDate = DateTime.now().toUtc();
  }

  // --- Tag management (Iteration 2, PRD §6.7 "tag documents") ---

  Tag? tagById(String id) {
    for (final t in tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  void renameTag(String id, String newName) {
    final tag = tagById(id);
    if (tag == null) {
      throw ArgumentError('No tag with id $id');
    }
    tag.name = newName;
  }

  /// Removes [id] from every entry that has it, and from the tag list.
  void deleteTag(String id) {
    for (final entry in entries) {
      if (entry.tagIds.remove(id)) {
        entry.modifiedDate = DateTime.now().toUtc();
      }
    }
    tags.removeWhere((t) => t.id == id);
  }

  /// Folds [sourceTagIds] into [targetTagId]: every entry tagged with a
  /// source tag is retagged to the target (without duplicating it), then the
  /// source tags are removed from the vault.
  void mergeTags(List<String> sourceTagIds, String targetTagId) {
    for (final entry in entries) {
      final hadSource = entry.tagIds.any(sourceTagIds.contains);
      if (!hadSource) continue;
      entry.tagIds = entry.tagIds.where((t) => !sourceTagIds.contains(t)).toList();
      if (!entry.tagIds.contains(targetTagId)) {
        entry.tagIds.add(targetTagId);
      }
      entry.modifiedDate = DateTime.now().toUtc();
    }
    tags.removeWhere((t) => sourceTagIds.contains(t.id));
  }

  void addTagToEntry(String entryId, String tagId) {
    final entry = entryById(entryId);
    if (entry == null) {
      throw ArgumentError('No entry with id $entryId');
    }
    if (!entry.tagIds.contains(tagId)) {
      entry.tagIds.add(tagId);
      entry.modifiedDate = DateTime.now().toUtc();
    }
  }

  void removeTagFromEntry(String entryId, String tagId) {
    final entry = entryById(entryId);
    if (entry == null) {
      throw ArgumentError('No entry with id $entryId');
    }
    if (entry.tagIds.remove(tagId)) {
      entry.modifiedDate = DateTime.now().toUtc();
    }
  }

  // --- Search & filters (Iteration 3, PRD §12 "quick search and filters") ---

  /// Returns entries matching every given criterion. [query] matches
  /// case-insensitively against title, notes and OCR text (substring match;
  /// a stand-in for FTS5 until documents are indexed in a real search
  /// engine). All other filters are AND-ed together; tagIds requires an
  /// entry to have every listed tag.
  List<Entry> search({
    String? query,
    String? mimeType,
    List<String> tagIds = const [],
    String? folderId,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool? favouritesOnly,
    bool includeArchived = false,
  }) {
    final needle = query?.trim().toLowerCase();
    return entries.where((e) {
      if (!includeArchived && e.isArchived) return false;
      if (favouritesOnly == true && !e.isFavourite) return false;
      if (mimeType != null && e.mimeType != mimeType) return false;
      if (folderId != null && e.folderId != folderId) return false;
      if (tagIds.isNotEmpty && !tagIds.every(e.tagIds.contains)) return false;
      final docDate = e.documentDate ?? e.addedDate;
      if (dateFrom != null && docDate.isBefore(dateFrom)) return false;
      if (dateTo != null && docDate.isAfter(dateTo)) return false;
      if (needle != null && needle.isNotEmpty) {
        final haystack = [e.title, e.notes, e.ocrText ?? '']
            .join(' ')
            .toLowerCase();
        if (!haystack.contains(needle)) return false;
      }
      return true;
    }).toList();
  }

  List<Entry> get favourites =>
      entries.where((e) => e.isFavourite && !e.isArchived).toList();

  List<Entry> get archived => entries.where((e) => e.isArchived).toList();

  void setFavourite(String entryId, bool value) {
    final entry = entryById(entryId);
    if (entry == null) {
      throw ArgumentError('No entry with id $entryId');
    }
    entry.isFavourite = value;
    entry.modifiedDate = DateTime.now().toUtc();
  }

  void setArchived(String entryId, bool value) {
    final entry = entryById(entryId);
    if (entry == null) {
      throw ArgumentError('No entry with id $entryId');
    }
    entry.isArchived = value;
    entry.modifiedDate = DateTime.now().toUtc();
  }
}
