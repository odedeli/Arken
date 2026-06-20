// Logical vault entities, per PRD §9 (Data Model). These are the contents of
// the encrypted index; exact on-disk storage is an implementation detail
// owned by VaultIndex/Vault.
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// §9.1 Folder — forms a tree via [parentId].
class Folder {
  final String id;
  String name;
  String? parentId;

  Folder({String? id, required this.name, this.parentId}) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
      };

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String?,
      );
}

/// §9.1 Tag — optional colour, used both standalone and via "Variable (tags)"
/// custom fields (§9.3).
class Tag {
  final String id;
  String name;
  String? colour;

  Tag({String? id, required this.name, this.colour}) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colour': colour,
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id'] as String,
        name: json['name'] as String,
        colour: json['colour'] as String?,
      );
}

/// §9.3 Supported custom field types.
enum FieldType {
  boolean,
  text,
  richText,
  integer,
  floatingPoint,
  calculation,
  date,
  time,
  dateTime,
  duration,
  singleChoice,
  multipleChoice,
  tags,
}

/// §9.1 FieldDefinition — a user-defined custom field.
class FieldDefinition {
  final String id;
  String name;
  FieldType type;
  List<String>? options; // for choice types
  String? inputMask;
  dynamic defaultValue;
  bool required;
  String? calculationFormula; // for FieldType.calculation
  String? appliesToFolderId; // category/folder this field is scoped to

  FieldDefinition({
    String? id,
    required this.name,
    required this.type,
    this.options,
    this.inputMask,
    this.defaultValue,
    this.required = false,
    this.calculationFormula,
    this.appliesToFolderId,
  }) : id = id ?? newId();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'options': options,
        'inputMask': inputMask,
        'defaultValue': defaultValue,
        'required': required,
        'calculationFormula': calculationFormula,
        'appliesToFolderId': appliesToFolderId,
      };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) => FieldDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        type: FieldType.values.byName(json['type'] as String),
        options: (json['options'] as List?)?.cast<String>(),
        inputMask: json['inputMask'] as String?,
        defaultValue: json['defaultValue'],
        required: json['required'] as bool? ?? false,
        calculationFormula: json['calculationFormula'] as String?,
        appliesToFolderId: json['appliesToFolderId'] as String?,
      );
}

/// §9.1 FieldValue — the typed value of a FieldDefinition on a specific Entry.
class FieldValue {
  final String fieldDefinitionId;
  dynamic value;

  FieldValue({required this.fieldDefinitionId, this.value});

  Map<String, dynamic> toJson() => {
        'fieldDefinitionId': fieldDefinitionId,
        'value': value,
      };

  factory FieldValue.fromJson(Map<String, dynamic> json) => FieldValue(
        fieldDefinitionId: json['fieldDefinitionId'] as String,
        value: json['value'],
      );
}

/// §9.1 FieldSet — a named template of field definitions (§6.3, §6.8).
class FieldSet {
  final String id;
  String name;
  List<FieldDefinition> fields;

  FieldSet({String? id, required this.name, List<FieldDefinition>? fields})
      : id = id ?? newId(),
        fields = fields ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  factory FieldSet.fromJson(Map<String, dynamic> json) => FieldSet(
        id: json['id'] as String,
        name: json['name'] as String,
        fields: (json['fields'] as List)
            .map((f) => FieldDefinition.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
}

/// §9.2 Entry — a stored document and its properties.
class Entry {
  final String id;
  String title;
  String folderId;
  String category;
  DateTime? documentDate;
  DateTime addedDate;
  DateTime modifiedDate;
  String notes;
  List<FieldValue> customFields;
  String fileName;
  String mimeType;
  int fileSize;
  String checksum; // links to FileBlob, content-addressed
  String? ocrText;
  bool isFavourite;
  bool isArchived;
  List<String> tagIds;

  Entry({
    String? id,
    required this.title,
    required this.folderId,
    this.category = '',
    this.documentDate,
    DateTime? addedDate,
    DateTime? modifiedDate,
    this.notes = '',
    List<FieldValue>? customFields,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.checksum,
    this.ocrText,
    this.isFavourite = false,
    this.isArchived = false,
    List<String>? tagIds,
  })  : id = id ?? newId(),
        addedDate = addedDate ?? DateTime.now().toUtc(),
        modifiedDate = modifiedDate ?? DateTime.now().toUtc(),
        customFields = customFields ?? [],
        tagIds = tagIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'folderId': folderId,
        'category': category,
        'documentDate': documentDate?.toIso8601String(),
        'addedDate': addedDate.toIso8601String(),
        'modifiedDate': modifiedDate.toIso8601String(),
        'notes': notes,
        'customFields': customFields.map((f) => f.toJson()).toList(),
        'fileName': fileName,
        'mimeType': mimeType,
        'fileSize': fileSize,
        'checksum': checksum,
        'ocrText': ocrText,
        'isFavourite': isFavourite,
        'isArchived': isArchived,
        'tagIds': tagIds,
      };

  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
        id: json['id'] as String,
        title: json['title'] as String,
        folderId: json['folderId'] as String,
        category: json['category'] as String? ?? '',
        documentDate: json['documentDate'] == null
            ? null
            : DateTime.parse(json['documentDate'] as String),
        addedDate: DateTime.parse(json['addedDate'] as String),
        modifiedDate: DateTime.parse(json['modifiedDate'] as String),
        notes: json['notes'] as String? ?? '',
        customFields: (json['customFields'] as List? ?? [])
            .map((f) => FieldValue.fromJson(f as Map<String, dynamic>))
            .toList(),
        fileName: json['fileName'] as String,
        mimeType: json['mimeType'] as String,
        fileSize: json['fileSize'] as int,
        checksum: json['checksum'] as String,
        ocrText: json['ocrText'] as String?,
        isFavourite: json['isFavourite'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
        tagIds: (json['tagIds'] as List? ?? []).cast<String>(),
      );
}
