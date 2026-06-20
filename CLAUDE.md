# Arken — project memory

Source of truth: `Docs/Arken - Paperless Document Cabinet - PRD v1.0.docx`.
Read it before making product or architecture decisions; this file is a
pointer and quick-reference, not a replacement.

## What Arken is

A secure, offline-first, paperless document cabinet. A single encrypted
vault (KeePass-style: master password unlocks everything) holds household
documents and their metadata. Client-only — no server backend. Cross-device
via an optional Google Drive sync of the vault file. See PRD §1–§5.

## Stack (fixed, PRD §10)

- **Flutter (Dart)** — one codebase: Windows, Linux (Mint/Cinnamon, KDE
  Plasma), Android. No iOS/macOS/web.
- Crypto: Argon2id KDF, ChaCha20-Poly1305 AEAD (`cryptography` package).
- Vault format: a directory package — `header.json` (plaintext format/KDF
  params) + `index.enc` (AEAD-sealed folders/tags/entries/fields) +
  `blobs/<sha256>.enc` (content-addressed, individually encrypted document
  blobs). See `app/lib/src/vault/vault_format.dart` and PRD §10.2.
- Local app code lives under `app/` (standard `flutter create` layout).

## Conventions

- Work one PRD roadmap iteration (§12) or one task at a time — never the
  whole app in one prompt.
- Task template: Context (cite PRD §) → Task → Constraints → Acceptance
  criteria → Out of scope.
- State target platform(s) and whether the change must stay fully offline.
- Prefer small, verifiable steps with tests over large multi-feature diffs.
- Versioning: SemVer; pre-1.0 vault format may change between 0.x releases,
  frozen at 1.0. Codenames are gemstones, A→Z (0.1 Amber, 0.2 Beryl, ...).
  See PRD §2.3–2.4.

## Roadmap status (PRD §12)

- [x] Iteration 1 — Encrypted vault core (desktop first): vault format,
      Argon2id + ChaCha20-Poly1305, create/open/lock, folders/tags/entries
      data layer, minimal UI to import a file and see it listed. Scaffolded
      in `app/`; see `app/lib/src/vault/`.
- [ ] Iteration 2 — Capture, organise & view
- [ ] Iteration 3 — Search & metadata depth
- [ ] Iteration 4 — Android build
- [ ] Iteration 5 — Google Drive sync & import
- [ ] Iteration 6 — Hardening & polish

## Running

```
cd app
flutter pub get
flutter test          # crypto + vault round-trip tests (headless, no display needed)
flutter run -d linux   # or -d windows
```
