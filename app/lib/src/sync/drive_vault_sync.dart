// Google Drive sync for a vault directory (PRD §12 Iteration 5). Uploads or
// downloads the whole vault package (header.json, index.enc, blobs/*) to a
// single named folder in the signed-in user's Drive — the vault stays
// client-encrypted; Drive only ever stores the same sealed bytes that sit on
// disk locally, so this requires no server-side trust.
//
// Sign-in and the Drive REST calls need real OAuth credentials (a Google
// Cloud project with the Drive API enabled, plus a configured client ID).
// Wire those up via `google_sign_in`'s platform configuration before this
// can run end-to-end; see https://pub.dev/packages/google_sign_in.
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../vault/vault_format.dart';
import 'drive_sync_planner.dart';

const _driveFolderName = 'Arken Vault';
const _syncStateFileName = '.drive_sync_state.json';

/// Thrown when local and remote both changed since the last sync and the
/// caller hasn't told us which side wins.
class DriveSyncConflictException implements Exception {
  final DateTime localModifiedAt;
  final DateTime remoteModifiedAt;
  DriveSyncConflictException(this.localModifiedAt, this.remoteModifiedAt);

  @override
  String toString() =>
      'DriveSyncConflictException: local changed at $localModifiedAt, '
      'remote changed at $remoteModifiedAt — resolve manually.';
}

class DriveVaultSync {
  static final _googleSignIn = GoogleSignIn(scopes: [drive.DriveApi.driveFileScope]);

  static Future<GoogleSignInAccount?> signIn() => _googleSignIn.signIn();

  static Future<void> signOut() => _googleSignIn.signOut();

  /// Builds an authenticated Drive API client for the currently signed-in
  /// account (call [signIn] first).
  static Future<drive.DriveApi> _apiFor(GoogleSignInAccount account) async {
    final authHeaders = await account.authHeaders;
    final client = _HeaderHttpClient(authHeaders);
    return drive.DriveApi(client);
  }

  static Future<String> _ensureVaultFolder(drive.DriveApi api) async {
    final existing = await api.files.list(
      q: "name = '$_driveFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    final found = existing.files;
    if (found != null && found.isNotEmpty) return found.first.id!;

    final folder = drive.File(
      name: _driveFolderName,
      mimeType: 'application/vnd.google-apps.folder',
    );
    final created = await api.files.create(folder);
    return created.id!;
  }

  static Future<String?> _findFileId(
    drive.DriveApi api,
    String folderId,
    String relativePath,
  ) async {
    final result = await api.files.list(
      q: "name = '${p.basename(relativePath)}' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    final files = result.files;
    return (files != null && files.isNotEmpty) ? files.first.id : null;
  }

  /// Reads just the remote header.json's `modifiedAt`, without downloading
  /// the rest of the vault — used for conflict detection before deciding
  /// whether a full sync is needed.
  static Future<DateTime?> remoteModifiedAt(
    GoogleSignInAccount account,
    String folderId,
  ) async {
    final api = await _apiFor(account);
    final headerId = await _findFileId(api, folderId, headerFileName);
    if (headerId == null) return null;
    final media = await api.files.get(
      headerId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = await _collectBytes(media.stream);
    final header = VaultHeader.decodeJson(String.fromCharCodes(bytes));
    return header.modifiedAt;
  }

  static File _syncStateFile(Directory vaultDir) =>
      File(p.join(vaultDir.path, _syncStateFileName));

  /// The last time this local vault directory was confirmed in sync with
  /// Drive (plaintext, not sensitive — just a timestamp).
  static Future<DateTime?> lastSyncedAt(Directory vaultDir) async {
    final file = _syncStateFile(vaultDir);
    if (!await file.exists()) return null;
    return DateTime.tryParse(await file.readAsString());
  }

  static Future<void> _recordSynced(Directory vaultDir, DateTime at) =>
      _syncStateFile(vaultDir).writeAsString(at.toIso8601String());

  /// Determines what action is needed, then performs it. Throws
  /// [DriveSyncConflictException] if both sides changed since the last sync
  /// — call [forceUpload] or [forceDownload] to resolve.
  static Future<SyncAction> sync(GoogleSignInAccount account, Directory vaultDir) async {
    final api = await _apiFor(account);
    final folderId = await _ensureVaultFolder(api);

    final localHeader = VaultHeader.decodeJson(
      await File(p.join(vaultDir.path, headerFileName)).readAsString(),
    );
    final remoteAt = await remoteModifiedAt(account, folderId);
    final lastSynced = await lastSyncedAt(vaultDir);

    final action = DriveSyncPlanner.decide(
      localModifiedAt: localHeader.modifiedAt,
      remoteModifiedAt: remoteAt,
      lastSyncedAt: lastSynced,
    );

    switch (action) {
      case SyncAction.upToDate:
        break;
      case SyncAction.uploadLocal:
        await _uploadAll(api, folderId, vaultDir);
        await _recordSynced(vaultDir, localHeader.modifiedAt);
        break;
      case SyncAction.downloadRemote:
        await _downloadAll(api, folderId, vaultDir);
        final synced = await lastSyncedAt(vaultDir);
        await _recordSynced(vaultDir, remoteAt ?? synced ?? DateTime.now().toUtc());
        break;
      case SyncAction.conflict:
        throw DriveSyncConflictException(localHeader.modifiedAt, remoteAt!);
    }
    return action;
  }

  static Future<void> forceUpload(GoogleSignInAccount account, Directory vaultDir) async {
    final api = await _apiFor(account);
    final folderId = await _ensureVaultFolder(api);
    await _uploadAll(api, folderId, vaultDir);
    final header = VaultHeader.decodeJson(
      await File(p.join(vaultDir.path, headerFileName)).readAsString(),
    );
    await _recordSynced(vaultDir, header.modifiedAt);
  }

  static Future<void> forceDownload(GoogleSignInAccount account, Directory vaultDir) async {
    final api = await _apiFor(account);
    final folderId = await _ensureVaultFolder(api);
    await _downloadAll(api, folderId, vaultDir);
    final at = await remoteModifiedAt(account, folderId) ?? DateTime.now().toUtc();
    await _recordSynced(vaultDir, at);
  }

  static Future<void> _uploadAll(
    drive.DriveApi api,
    String folderId,
    Directory vaultDir,
  ) async {
    for (final relativePath in await _vaultRelativePaths(vaultDir)) {
      final localFile = File(p.join(vaultDir.path, relativePath));
      final bytes = await localFile.readAsBytes();
      final existingId = await _findFileId(api, folderId, relativePath);
      final media = drive.Media(Stream.value(bytes), bytes.length);
      if (existingId != null) {
        await api.files.update(drive.File(), existingId, uploadMedia: media);
      } else {
        await api.files.create(
          drive.File(name: p.basename(relativePath), parents: [folderId]),
          uploadMedia: media,
        );
      }
    }
  }

  static Future<void> _downloadAll(
    drive.DriveApi api,
    String folderId,
    Directory vaultDir,
  ) async {
    final result = await api.files.list(
      q: "'$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    for (final remoteFile in result.files ?? <drive.File>[]) {
      final media = await api.files.get(
        remoteFile.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = await _collectBytes(media.stream);
      final localFile = File(p.join(vaultDir.path, remoteFile.name!));
      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(bytes, flush: true);
    }
  }

  /// header.json, index.enc, and every blob — the full vault package.
  static Future<List<String>> _vaultRelativePaths(Directory vaultDir) async {
    final paths = <String>[headerFileName, indexFileName];
    final blobsDir = Directory(p.join(vaultDir.path, blobsDirName));
    if (await blobsDir.exists()) {
      await for (final entity in blobsDir.list()) {
        if (entity is File) {
          paths.add(p.join(blobsDirName, p.basename(entity.path)));
        }
      }
    }
    return paths;
  }

  static Future<List<int>> _collectBytes(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}

/// A minimal [http.BaseClient] that attaches the given auth headers to every
/// request, as required by `googleapis` clients.
class _HeaderHttpClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _HeaderHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
