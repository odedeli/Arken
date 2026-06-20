// Decides what a Google Drive sync should do for a vault, given local and
// remote modification times and the time of the last successful sync
// (PRD §12 Iteration 5 "sync the vault file to/from Drive with conflict
// detection"). Pure decision logic, deliberately free of any Drive API or
// filesystem access so it can be unit tested without network access.

enum SyncAction {
  /// Local and remote already agree; nothing to do.
  upToDate,

  /// Only the local vault changed since the last sync (or there is no
  /// remote vault yet) — push local to Drive.
  uploadLocal,

  /// Only the remote vault changed since the last sync (or there is no
  /// local vault yet) — pull from Drive.
  downloadRemote,

  /// Both sides changed since the last sync (or this is the first sync and
  /// they disagree) — can't tell which is authoritative; the caller must
  /// ask the user to pick a side.
  conflict,
}

class DriveSyncPlanner {
  /// [lastSyncedAt] is the local record of when this vault was last known to
  /// match Drive (null if it has never been synced before).
  static SyncAction decide({
    required DateTime? localModifiedAt,
    required DateTime? remoteModifiedAt,
    required DateTime? lastSyncedAt,
  }) {
    if (remoteModifiedAt == null) return SyncAction.uploadLocal;
    if (localModifiedAt == null) return SyncAction.downloadRemote;

    if (lastSyncedAt == null) {
      return localModifiedAt.isAtSameMomentAs(remoteModifiedAt)
          ? SyncAction.upToDate
          : SyncAction.conflict;
    }

    final localChanged = localModifiedAt.isAfter(lastSyncedAt);
    final remoteChanged = remoteModifiedAt.isAfter(lastSyncedAt);

    if (!localChanged && !remoteChanged) return SyncAction.upToDate;
    if (localChanged && !remoteChanged) return SyncAction.uploadLocal;
    if (!localChanged && remoteChanged) return SyncAction.downloadRemote;
    return SyncAction.conflict;
  }
}
