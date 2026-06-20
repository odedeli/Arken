# Arken — Sprints, Versions & Codenames

Tracks progress against the PRD (`Docs/Arken - Paperless Document Cabinet - PRD v1.0.docx`)
§12 roadmap. Codenames are gemstones, A→Z. Pre-1.0 versions are 0.x and the
vault format may still change between them; format freezes at 1.0 (PRD §2.3–2.4).

| Sprint | Version | Codename | Status | Scope (PRD §12) |
|---|---|---|---|---|
| 1 | 0.1 | Amber | Done | Encrypted vault core (desktop first): vault format, Argon2id + ChaCha20-Poly1305, create/open/lock, folders/tags/entries data layer, minimal UI to import a file and see it listed. |
| 2 | 0.2 | Beryl | Mostly done | Capture, organise & view. Step 1 (folder/tag/move data-layer ops in `VaultIndex`) done & tested. Step 2 — responsive two-pane UI (`LibraryView`, sidebar collapses to a `Drawer` below 700px), file-picker/camera import, folder/tag management dialogs, search/filter wiring, favourites/archive toggles — done & tested (widget test in `library_view_test.dart`). Step 3 (in-app preview + open/export) **not yet implemented** — deferred. |
| 3 | 0.3 | Citrine | In progress | Search & metadata depth: quick search and filters (type, tag, date); text extraction from PDFs and full-text search (FTS5); typed custom fields with input masks (§9.3), favourites, and archive. Outcome: fast retrieval across a realistic document set. |
| 4 | 0.4 | Diamond | In progress | Android build: port the app to Android with a touch-adapted UI; capture via camera / system document scan. Outcome: the same vault opens and works on a phone. Android platform scaffolded, camera permission added, file/camera pickers replace the typed-path import flow, vault path defaults to the app's documents directory. Not yet built/run on a device or emulator — no Android SDK in this sandbox. |
| 5 | 0.5 | Emerald | In progress | Google Drive sync & import: Google Sign-In and Drive file picker to import documents; sync the vault file to/from Drive with conflict detection. Outcome: one vault shared across desktop and Android via Drive. Conflict-detection logic (`DriveSyncPlanner`, unit-tested) and the upload/download engine (`DriveVaultSync`) are done, with a "Sync with Drive" toolbar action and a manual-resolution dialog for true conflicts. Drive's file picker for importing existing documents (as opposed to syncing the vault itself) is not yet implemented. **Untested against live Drive**: this needs a real Google Cloud project (Drive API enabled, OAuth client ID configured for desktop, `google-services.json` for Android) that only the project owner can set up — see the doc comment at the top of `drive_vault_sync.dart`. |
| 6 | 1.0 | Fluorite | Not started | Hardening & polish: OCR for scanned images, automatic backups, auto-lock, theming and accessibility; optional unlock methods (biometrics, Windows Hello, passkeys, authenticator 2FA, §6.7); integrity checks, vault-format migration path, broader file-type previews. Outcome: a dependable daily-use application. Vault format freezes here.

## Notes

- Per user direction (2026-06-20), strict test-and-verify gating between
  iterations is relaxed for v0.2 Beryl: its data-layer step is accepted as
  complete-enough to move on, with the UI/preview steps left open and
  revisited later rather than blocking Sprint 3.
- This file is the quick-reference for "what version/codename am I on";
  `CLAUDE.md` §"Roadmap status" remains the canonical PRD-aligned checklist
  and should be kept in sync with this table.
