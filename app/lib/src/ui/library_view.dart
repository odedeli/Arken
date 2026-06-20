// Browse/organise screen — Iteration 2 step 2 (PRD §12 "three-pane UI,
// folder/tag management UI"), simplified to a responsive two-pane layout
// (folder/tag sidebar + entry list) since the desktop-only three-pane split
// (folders | entries | preview) needs in-app preview (still deferred) to be
// worth the extra pane. On narrow (phone) widths the sidebar collapses into
// a Drawer.
import 'package:flutter/material.dart';

import '../vault/models.dart';
import '../vault/vault.dart';

const _kWideLayoutBreakpoint = 700.0;

class LibraryView extends StatefulWidget {
  final Vault vault;
  final bool busy;
  final String? topError;
  final VoidCallback onImportFile;
  final VoidCallback onCaptureFile;

  const LibraryView({
    super.key,
    required this.vault,
    required this.busy,
    required this.topError,
    required this.onImportFile,
    required this.onCaptureFile,
  });

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  String? _selectedFolderId; // null = All documents
  final Set<String> _selectedTagIds = {};
  final _searchController = TextEditingController();
  bool _favouritesOnly = false;
  bool _showArchived = false;
  String? _localError;

  Vault get _vault => widget.vault;

  Future<void> _persist() async {
    await _vault.save();
    if (mounted) setState(() {});
  }

  Future<void> _runOrShowError(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      setState(() => _localError = e.toString());
      return;
    }
    setState(() => _localError = null);
  }

  List<Entry> get _visibleEntries => _vault.index.search(
        query: _searchController.text,
        folderId: _selectedFolderId,
        tagIds: _selectedTagIds.toList(),
        favouritesOnly: _favouritesOnly ? true : null,
        includeArchived: _showArchived,
      );

  @override
  Widget build(BuildContext context) {
    final sidebar = _buildSidebar(context);
    final content = _buildContent(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kWideLayoutBreakpoint;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(width: 260, child: sidebar),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          drawer: Drawer(child: sidebar),
          body: Builder(
            builder: (context) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu),
                        tooltip: 'Folders & tags',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                      Text(
                        _selectedFolderId == null
                            ? 'All documents'
                            : _vault.index.folderById(_selectedFolderId!)?.name ??
                                'All documents',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final folders = _vault.index.folders;
    final tags = _vault.index.tags;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text('All documents'),
          selected: _selectedFolderId == null,
          onTap: () => setState(() => _selectedFolderId = null),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: _SectionLabel('Folders'),
        ),
        for (final folder in folders)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder.name),
            selected: _selectedFolderId == folder.id,
            onTap: () => setState(() => _selectedFolderId = folder.id),
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _onFolderAction(action, folder),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: OutlinedButton.icon(
            onPressed: _addFolder,
            icon: const Icon(Icons.add),
            label: const Text('New folder'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: _SectionLabel('Tags'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                FilterChip(
                  label: Text(tag.name),
                  selected: _selectedTagIds.contains(tag.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _selectedTagIds.add(tag.id);
                    } else {
                      _selectedTagIds.remove(tag.id);
                    }
                  }),
                  onDeleted: () => _runOrShowError(() async {
                    _vault.index.deleteTag(tag.id);
                    _selectedTagIds.remove(tag.id);
                    await _persist();
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: OutlinedButton.icon(
            onPressed: _addTag,
            icon: const Icon(Icons.add),
            label: const Text('New tag'),
          ),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Favourites only'),
          value: _favouritesOnly,
          onChanged: (v) => setState(() => _favouritesOnly = v),
        ),
        SwitchListTile(
          title: const Text('Show archived'),
          value: _showArchived,
          onChanged: (v) => setState(() => _showArchived = v),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final entries = _visibleEntries;
    final error = widget.topError ?? _localError;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search title, notes, OCR text…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: widget.busy ? null : widget.onImportFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Import'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onCaptureFile,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Scan'),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No documents match. Import one, or adjust filters.'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _EntryTile(
                    entry: entries[i],
                    vault: _vault,
                    onToggleFavourite: () => _runOrShowError(() async {
                      _vault.index.setFavourite(entries[i].id, !entries[i].isFavourite);
                      await _persist();
                    }),
                    onToggleArchived: () => _runOrShowError(() async {
                      _vault.index.setArchived(entries[i].id, !entries[i].isArchived);
                      await _persist();
                    }),
                    onMoveToFolder: (folderId) => _runOrShowError(() async {
                      _vault.index.moveEntry(entries[i].id, folderId);
                      await _persist();
                    }),
                    onManageTags: () => _showManageTagsSheet(entries[i]),
                  ),
                ),
        ),
      ],
    );
  }

  void _onFolderAction(String action, Folder folder) {
    if (action == 'rename') {
      _renameFolder(folder);
    } else if (action == 'delete') {
      _deleteFolder(folder);
    }
  }

  Future<void> _addFolder() async {
    final name = await _promptForText(title: 'New folder', label: 'Folder name');
    if (name == null || name.trim().isEmpty) return;
    await _runOrShowError(() async {
      _vault.index.addFolder(name.trim());
      await _persist();
    });
  }

  Future<void> _renameFolder(Folder folder) async {
    final name = await _promptForText(
      title: 'Rename folder',
      label: 'Folder name',
      initialValue: folder.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await _runOrShowError(() async {
      _vault.index.renameFolder(folder.id, name.trim());
      await _persist();
    });
  }

  Future<void> _deleteFolder(Folder folder) async {
    final hasEntries = _vault.index.entries.any((e) => e.folderId == folder.id);
    String? destinationId = folder.parentId;
    if (hasEntries && destinationId == null) {
      // Promote into another top-level folder rather than blocking outright.
      destinationId = _vault.index.folders.firstWhere(
        (f) => f.id != folder.id,
        orElse: () => folder,
      ).id;
      if (destinationId == folder.id) {
        setState(() => _localError =
            'Cannot delete "${folder.name}": it has documents and there is '
            'no other folder to move them to.');
        return;
      }
    }
    await _runOrShowError(() async {
      _vault.index.deleteFolder(folder.id, moveContentsTo: destinationId);
      if (_selectedFolderId == folder.id) _selectedFolderId = null;
      await _persist();
    });
  }

  Future<void> _addTag() async {
    final name = await _promptForText(title: 'New tag', label: 'Tag name');
    if (name == null || name.trim().isEmpty) return;
    await _runOrShowError(() async {
      _vault.index.addTag(name.trim());
      await _persist();
    });
  }

  Future<String?> _promptForText({
    required String title,
    required String label,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManageTagsSheet(Entry entry) {
    return showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tags for "${entry.title}"', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _vault.index.tags)
                      FilterChip(
                        label: Text(tag.name),
                        selected: entry.tagIds.contains(tag.id),
                        onSelected: (selected) {
                          setSheetState(() {
                            if (selected) {
                              _vault.index.addTagToEntry(entry.id, tag.id);
                            } else {
                              _vault.index.removeTagFromEntry(entry.id, tag.id);
                            }
                          });
                          _persist();
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
            letterSpacing: 0.5,
          ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Entry entry;
  final Vault vault;
  final VoidCallback onToggleFavourite;
  final VoidCallback onToggleArchived;
  final void Function(String folderId) onMoveToFolder;
  final VoidCallback onManageTags;

  const _EntryTile({
    required this.entry,
    required this.vault,
    required this.onToggleFavourite,
    required this.onToggleArchived,
    required this.onMoveToFolder,
    required this.onManageTags,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(entry.title),
      subtitle: Text(
        '${entry.fileName} · ${entry.fileSize} bytes'
        '${entry.isArchived ? ' · Archived' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(entry.isFavourite ? Icons.star : Icons.star_border),
            tooltip: entry.isFavourite ? 'Unfavourite' : 'Favourite',
            onPressed: onToggleFavourite,
          ),
          IconButton(
            icon: Icon(entry.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
            tooltip: entry.isArchived ? 'Unarchive' : 'Archive',
            onPressed: onToggleArchived,
          ),
          PopupMenuButton<Object>(
            onSelected: (value) {
              if (value == 'tags') {
                onManageTags();
              } else if (value is String) {
                onMoveToFolder(value);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'tags', child: Text('Manage tags…')),
              const PopupMenuDivider(),
              for (final folder in vault.index.folders)
                PopupMenuItem(value: folder.id, child: Text('Move to "${folder.name}"')),
            ],
          ),
        ],
      ),
    );
  }
}
