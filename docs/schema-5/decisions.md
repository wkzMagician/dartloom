# Schema 5 decisions

These decisions are the shared contract for the later Dartloom, Mini Todo, and
MindBubble stages. Application-specific details belong in the application
repositories.

## 1. Schema and compatibility

- The target configuration value is `schema_version: 5`.
- The CLI must migrate schema 4 to schema 5 explicitly and safely.
- A failed migration leaves the original configuration and its validated
  backup recoverable; it must not partially rewrite the active configuration.
- Dartloom remains a `0.x` API. Breaking renames and removals are allowed, but
  every public contract change must be documented and covered by tests.
- Applications pin and verify one Dartloom schema-5 commit before migration.

## 2. Business paths belong to applications

Dartloom provides adapters and capability contracts. It does not invent a
business directory such as `AppSupport/Dartloom/<business-data>`.

Applications resolve their platform directories with their own path-provider
logic, then pass absolute paths into application-owned factories. Dartloom may
own technical state below an application-provided support root, but it must not
mix that state into the application's business document directory.

## 3. Observed state versus intent

The framework distinguishes observed replica state from authorized local
intent:

- A scan, external edit, external deletion, missing object, or unregistered
  file is observed state and does not create a synchronization intent.
- An authorized create, update, or delete operation creates one durable intent.
- Application and authorized MCP writes use the same intent semantics.
- A write is atomic from the application's point of view: business data and
  its intent cannot be reported as successfully committed when only one side
  succeeded.
- Remote state can restore local observed state; it must not manufacture a
  local user intent.

## 4. Replica storage direction

The storage abstraction must support raw bytes and metadata, not only JSON.
JSON codecs remain application adapters. File and directory replicas must
provide safe key validation, atomic writes, deterministic identity, change
observation, and a clear distinction between local authorized mutations and
replica recovery.

The storage contract must not assume that every synchronized object is a JSON
map. MindBubble Markdown and Mini Todo JSON files are both valid consumers of
the same lower-level replica model.

## 5. Synchronization safety

- External edits are not automatically uploaded as intents.
- External new files remain unregistered until an explicit import operation.
- External deletions are not automatically propagated as deletes.
- Remote baseline discovery and partial/failed listings never trigger bulk
  deletion.
- Old remote directories are preserved during migration; migration is
  additive and fills only missing objects in the new location.
- ETag/conditional operations and conflict policies remain authoritative; the
  refactor must not silently reduce field-level merge behavior to last-write
  wins.

## 6. Backup and migration safety

Backup precedes migration. A backup is immutable, uniquely named, and
manifested with per-file SHA-256 values. The migration sequence is:

1. Resolve source and destination paths through the application.
2. Create a new backup directory.
3. Copy files without following an unsafe path outside the source tree.
4. Write and validate the manifest.
5. Only then perform migration or rewrite operations.

If any step fails, stop and preserve the source. Recovery uses the manifest to
restore into a temporary directory, validates hashes, and only then allows an
operator or application-specific migration step to switch paths.

## 7. Runtime and settings direction

The runtime will gain an instance-oriented `DartloomRuntime` while retaining a
compatibility facade for the current `Dartloom` access pattern during the
schema-5 transition. Initialization must be isolated, dispose in reverse
creation order, and clean up already-created bindings after a later binding
fails. Capability registration must distinguish foreground, background, and
both scopes.

Settings retain simple typed access where useful, but structured JSON values
must have an explicit codec/contract. Secrets remain in secure storage and
must not enter ordinary settings, logs, or generated source.

## 8. Deferred implementation decisions

The following are intentionally left for their implementation stages, with the
constraints above binding the choice:

- exact `ReplicaStore` and change-event type names;
- the schema-4-to-schema-5 YAML transformation details;
- whether MindBubble MCP writes use local app IPC or a versioned append-only
  journal when IPC is unavailable;
- the final field-level merge policy implementation for Markdown.

The Stage 1 runtime API is now fixed as follows:

- `DartloomRuntime` owns an isolated registry and exposes `initialize`, `get`,
  `maybeGet`, `contains`, and `dispose`.
- `Dartloom` remains the compatibility facade backed by one default
  `DartloomRuntime`; existing static calls retain their meaning.
- `DartloomFactoryContext.get` resolves through the runtime that is currently
  initializing, not through the global facade.
- `DartloomStartupScope` and `DartloomRegistration.scope` support
  `foreground`, `background`, and `both`; runtime initialization defaults to
  foreground for compatibility.
- `SettingsJsonCodec` is the explicit structured-settings JSON contract. It
  preserves unknown object fields, accepts only JSON-compatible values, and
  reports malformed input with `FormatException`.

The Stage 2 storage API is fixed as follows:

- `ReplicaStore` is the generic raw-byte contract, with `StoreChange`,
  `ReplicaObjectMetadata`, and `StoreMutationOrigin`.
- `FileDirectoryStore` is the generic directory implementation in
  `dartloom_storage_text_file`; applications pass its absolute root through
  `openAt`.
- Existing `TextStore`, `JsonStore`, and `ReplicaJsonStore` remain available
  as compatibility contracts. JSON-specific codecs stay in
  `dartloom_storage_json_file`.
- External filesystem notifications are reported as replica-origin changes;
  they do not create authorized local intent.

Each choice must be recorded in this file or a linked application ADR before
the corresponding gate is marked passed.

## Stage 0 handoff

Stage 0 is complete when this file and `baseline.md` are committed on the
Dartloom feature branch, with all three repository worktrees recorded and no
application worktree changes overwritten. No merge or push is authorized by
this stage.
