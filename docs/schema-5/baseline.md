# Schema 5 refactor baseline

Collected 2026-08-14 (Asia/Shanghai) before implementation. This document is a
read-only record for the multi-repository refactor; it is not a claim that the
application repositories are clean.

## Repository state

| Repository | Path | Remote | Branch | HEAD | Worktree |
| --- | --- | --- | --- | --- | --- |
| Dartloom | `D:\FantasyProjects\dartloom` | `https://github.com/wkzMagician/dartloom.git` | `codex/replica-file-storage` | `8a84287b01ec8dabf92603caaf31e9f8c08a3789` | clean at branch creation; based on `main` and `origin/main` |
| Mini Todo | `D:\FantasyProjects\mini_todo` | `https://github.com/wkzMagician/mini-todo.git` | `main` | `304defdbf78357a3c972652f36de21a0ccd0a861` | user-modified `README.md`; preserve it |
| MindBubble | `D:\FantasyProjects\MindBubble` | `git@github.com:wkzMagician/MindBubble.git` | `main` | `898d63a35adfdba3285330d009f4ffa7a4952ee9` | documented pre-existing integration, formatting, locale/autostart, generated registrant, backup, installer, and related changes; preserve all |

Dartloom `main` and `origin/main` were aligned at collection time. The
MindBubble archive references remain present:

- tag `archive/mindbubble-0.4.0+5`
- branch `archive/mindbubble-0.4.0`

No application branch was created during Stage 0. The target Dartloom branch
is `codex/replica-file-storage`.

## Dartloom package inventory

The current package versions are:

| Package | Version |
| --- | --- |
| `dartloom` CLI | `0.2.2` |
| `dartloom_runtime` | `0.1.0` |
| `dartloom_settings` | `0.2.0` |
| `dartloom_storage` | `0.2.0` |
| `dartloom_storage_json_file` | `0.1.0` |
| `dartloom_storage_text_file` | `0.1.0` |
| `dartloom_sync` | `0.3.0` |
| `dartloom_sync_etag` | `0.2.0` |
| `dartloom_sync_storage` | `0.1.0` |
| `dartloom_sync_webdav` | `0.2.0` |
| `dartloom_sync_flutter` | `0.1.0` |
| `dartloom_sync_workmanager` | `0.1.0` |

Other capability packages at this baseline are `dartloom_autostart 0.2.0`,
`dartloom_autostart_launch_at_startup 0.1.0`, `dartloom_localization 0.2.0`,
`dartloom_localization_gen_l10n 0.1.0`, `dartloom_logging 0.2.0`,
`dartloom_logging_logger 0.1.0`, `dartloom_resident 0.3.0`,
`dartloom_resident_tray 0.2.1`, `dartloom_settings_secure_storage 0.1.0`,
and `dartloom_settings_shared_preferences 0.1.0`.

The current CLI accepts schema 4 and reports `schema_version: 4` as required.
Schema 5 migration behavior is therefore an implementation item, not an
existing capability.

## Application path facts

These are resolved by the applications with `path_provider`; they must not be
replaced with guessed or hard-coded platform paths.

### MindBubble

- Business documents: `getApplicationDocumentsDirectory()/MindBubble/bubbles`
- Application support state: `getApplicationSupportDirectory()/MindBubble`
- Current legacy database input: `getApplicationDocumentsDirectory()/mind_bubble.db`
- Current MCP default is environment-controlled by `MIND_BUBBLE_DIR`; its
  fallback is the user's Documents `MindBubble/bubbles` directory.
- Current remote implementation uses `/MindBubble/v2` and still recognizes
  `/MindBubble/devices`; the schema-5 target is `/MindBubble/bubbles/` with the
  old location retained for compatibility and recovery.

### Mini Todo

- Current `dartloom.yaml` is schema 4.
- The configured business path is `MiniTodo` through the app's
  `JsonDirectoryStore` path resolution.
- Current remote root is `MiniTodo`.
- Current metadata namespace is `mini_todo/sync-metadata/MiniTodo`.
- Existing object contract allows `.mini-todo.json` and `todo-` keys and keeps
  the legacy JSON source path/prefix for migration.

## Required backup record

Before either application migrates or rewrites local data, it must create a
new, non-overwriting backup directory and a manifest. The manifest must record
the source absolute path, backup absolute path, UTC creation time, application
version, relative file path, byte size, and SHA-256 for every copied file.
Failure to copy or validate any file stops the migration. Existing backups are
never overwritten. The backup must be validated before any migration writes to
the active business directory.

The current MindBubble `LocalDataBackupService` is only a preliminary safety
copy: it uses a one-time marker and does not yet provide the required manifest,
hash validation, or immutable backup naming contract. Stage 7B must replace or
extend it before the first Dartloom-backed data migration.

## Stage 0 boundary

Stage 0 changed only this baseline record and the accompanying decisions
record. It did not modify application code, application configuration,
lockfiles, generated files, or user data.
