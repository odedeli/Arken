import 'package:arken/src/sync/drive_sync_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);
  final t1 = DateTime.utc(2026, 1, 2);
  final t2 = DateTime.utc(2026, 1, 3);

  group('DriveSyncPlanner.decide', () {
    test('no remote vault yet uploads local', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t1,
          remoteModifiedAt: null,
          lastSyncedAt: null,
        ),
        SyncAction.uploadLocal,
      );
    });

    test('no local vault yet downloads remote', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: null,
          remoteModifiedAt: t1,
          lastSyncedAt: null,
        ),
        SyncAction.downloadRemote,
      );
    });

    test('first sync with matching timestamps is up to date', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t1,
          remoteModifiedAt: t1,
          lastSyncedAt: null,
        ),
        SyncAction.upToDate,
      );
    });

    test('first sync with differing timestamps is a conflict', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t1,
          remoteModifiedAt: t2,
          lastSyncedAt: null,
        ),
        SyncAction.conflict,
      );
    });

    test('neither side changed since last sync is up to date', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t0,
          remoteModifiedAt: t0,
          lastSyncedAt: t0,
        ),
        SyncAction.upToDate,
      );
    });

    test('only local changed uploads local', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t2,
          remoteModifiedAt: t0,
          lastSyncedAt: t0,
        ),
        SyncAction.uploadLocal,
      );
    });

    test('only remote changed downloads remote', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t0,
          remoteModifiedAt: t2,
          lastSyncedAt: t0,
        ),
        SyncAction.downloadRemote,
      );
    });

    test('both changed since last sync is a conflict', () {
      expect(
        DriveSyncPlanner.decide(
          localModifiedAt: t1,
          remoteModifiedAt: t2,
          lastSyncedAt: t0,
        ),
        SyncAction.conflict,
      );
    });
  });
}
