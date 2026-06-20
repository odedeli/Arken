// Arken — Iteration 1 (codename "Amber"): encrypted vault core, desktop
// first. Outcome (PRD §12): create a vault, add a file from disk, see it in
// a list, lock and reopen it. The three-pane desktop layout and previews land
// in a later UI pass; Iteration 4 (codename "Diamond") adds Android with
// file/camera pickers in place of typed file paths.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/sync/drive_sync_planner.dart';
import 'src/sync/drive_vault_sync.dart';
import 'src/vault/models.dart';
import 'src/vault/vault.dart';
import 'src/vault/vault_format.dart';

void main() {
  runApp(const ArkenApp());
}

class ArkenApp extends StatelessWidget {
  const ArkenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arken',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF267A7B), // Ambersky aqua-600 (§8.6)
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const VaultHomePage(),
    );
  }
}

class VaultHomePage extends StatefulWidget {
  const VaultHomePage({super.key});

  @override
  State<VaultHomePage> createState() => _VaultHomePageState();
}

class _VaultHomePageState extends State<VaultHomePage> {
  Vault? _vault;
  String? _error;
  bool _busy = false;

  final _pathController = TextEditingController();
  final _passwordController = TextEditingController();
  String _rootFolderId = '';

  @override
  void initState() {
    super.initState();
    _initDefaultVaultPath();
  }

  /// On Android there's no meaningful path for a user to type, so default to
  /// a vault folder under the app's own documents directory (still editable
  /// for desktop users who want a custom location).
  Future<void> _initDefaultVaultPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    if (!mounted) return;
    setState(() {
      _pathController.text = p.join(docsDir.path, 'arken_vault');
    });
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = _describeError(e));
    } finally {
      setState(() => _busy = false);
    }
  }

  String _describeError(Object e) {
    if (e is VaultAuthenticationException) {
      return 'Wrong master password, or the vault is corrupt.';
    }
    if (e is VaultFormatException) {
      return e.message;
    }
    return e.toString();
  }

  Future<void> _createVault() => _withBusy(() async {
        final vault = await Vault.create(
          directoryPath: _pathController.text,
          masterPassword: _passwordController.text,
        );
        final root = vault.index.addFolder('Home');
        await vault.save();
        setState(() {
          _vault = vault;
          _rootFolderId = root.id;
        });
      });

  Future<void> _openVault() => _withBusy(() async {
        final vault = await Vault.open(
          directoryPath: _pathController.text,
          masterPassword: _passwordController.text,
        );
        final root = vault.index.folders.isNotEmpty
            ? vault.index.folders.first.id
            : vault.index.addFolder('Home').id;
        setState(() {
          _vault = vault;
          _rootFolderId = root;
        });
      });

  void _lockVault() {
    _vault?.lock();
    setState(() => _vault = null);
  }

  Future<void> _addFile(String sourcePath) => _withBusy(() async {
        final vault = _vault!;
        await vault.addFile(sourcePath, folderId: _rootFolderId);
        await vault.save();
        setState(() {});
      });

  Future<void> _pickAndImportFile() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path != null) await _addFile(path);
  }

  /// Capture via camera, or a system document scan on platforms that route
  /// it through the same picker (PRD §12 Iteration 4 "capture via camera /
  /// system document scan").
  Future<void> _captureAndImport() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera);
    if (photo != null) await _addFile(photo.path);
  }

  /// Syncs the vault directory to/from Google Drive (PRD §12 Iteration 5).
  /// On conflict (both sides changed since the last sync), asks the user
  /// which copy should win rather than guessing.
  Future<void> _syncWithDrive() => _withBusy(() async {
        final account = await DriveVaultSync.signIn();
        if (account == null) return; // user cancelled sign-in
        final vaultDir = Directory(_pathController.text);
        try {
          final action = await DriveVaultSync.sync(account, vaultDir);
          if (action == SyncAction.downloadRemote) {
            // The on-disk vault changed under us; reopen it so the UI and
            // in-memory key/index reflect what's now on disk.
            await _openVault();
          }
        } on DriveSyncConflictException {
          if (!mounted) return;
          final keepLocal = await _resolveSyncConflict();
          if (keepLocal == null) return;
          if (keepLocal) {
            await DriveVaultSync.forceUpload(account, vaultDir);
          } else {
            await DriveVaultSync.forceDownload(account, vaultDir);
            await _openVault();
          }
        }
      });

  Future<bool?> _resolveSyncConflict() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sync conflict'),
          content: const Text(
            'This vault changed both here and on Drive since the last sync. '
            'Which copy should be kept?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep Drive copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Keep this device'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final vault = _vault;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arken'),
        actions: [
          if (vault != null)
            IconButton(
              icon: const Icon(Icons.cloud_sync_outlined),
              tooltip: 'Sync with Google Drive',
              onPressed: _busy ? null : _syncWithDrive,
            ),
          if (vault != null)
            IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock vault',
              onPressed: _lockVault,
            ),
        ],
      ),
      body: vault == null ? _buildUnlockView() : _buildLibraryView(vault),
    );
  }

  Widget _buildUnlockView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield_outlined, size: 48),
              const SizedBox(height: 12),
              Text(
                'Unlock or create a vault',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Vault folder path',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Master password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _createVault,
                      child: const Text('Create vault'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _openVault,
                      child: const Text('Open vault'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryView(Vault vault) {
    final entries = vault.index.entries;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _pickAndImportFile,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import file'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _captureAndImport,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Scan / camera'),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('No documents yet. Import one above.'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _EntryTile(entry: entries[i]),
                ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  final Entry entry;
  const _EntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(entry.title),
      subtitle: Text('${entry.fileName} · ${entry.fileSize} bytes'),
    );
  }
}
