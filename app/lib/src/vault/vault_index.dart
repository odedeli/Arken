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
}
