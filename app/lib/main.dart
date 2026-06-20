// Arken — Iteration 1 (codename "Amber"): encrypted vault core, desktop
// first. Outcome (PRD §12): create a vault, add a file from disk, see it in
// a list, lock and reopen it. The three-pane desktop layout, pickers, and
// previews land in Iteration 2.
import 'package:flutter/material.dart';

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

  final _pathController = TextEditingController(text: 'arken_vault');
  final _passwordController = TextEditingController();
  String _rootFolderId = '';

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

  @override
  Widget build(BuildContext context) {
    final vault = _vault;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arken'),
        actions: [
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
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'File path to import',
                    border: OutlineInputBorder(),
                    hintText: '/path/to/document.pdf',
                  ),
                  onSubmitted: _busy ? null : _addFile,
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
