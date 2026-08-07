# Dartloom

Dartloom is a configuration-driven capability framework and CLI for Flutter
applications. Feature code depends on stable contracts; `dartloom.yaml` selects
the production adapters installed and registered at startup.

## Install

Before the CLI is published to pub.dev:

```bash
dart install --overwrite https://github.com/wkzMagician/dartloom.git --git-path cli/dartloom_cli
```

After publication:

```bash
dart install dartloom
```

Update the installed CLI with `dartloom update`.

## Create and configure an application

```bash
dartloom new my_app --platforms=android,windows
cd my_app
dartloom cap
dartloom cap list
dartloom cap add localization
dartloom cap remove localization
```

`dartloom cap` is a keyboard-driven terminal editor. Use Up/Down to move,
Space to enable or disable, Enter to edit implementations and options, and the
Save row to apply the complete dependency change once.

Generated feature code obtains configured services from the runtime registry:

```dart
final settings = Dartloom.get<SettingsStore>();
final json = Dartloom.get<JsonStore>(name: 'json');
```

Application-owned adapters use a factory ID in `dartloom.yaml` and are supplied
to `initializeDartloom(customFactories: {...})`. Feature code should never
import adapter packages directly.

## Capability catalog

| Capability | Stable contract | Official implementation |
| --- | --- | --- |
| settings | portable settings values | shared_preferences, secure_storage |
| storage.text | UTF-8 text CRUD | atomic files |
| storage.json | JSON value CRUD | atomic JSON file |
| storage.database | collection/id document CRUD | Drift/SQLite |
| logging | application logger | logger |
| autostart | enable/disable startup | launch_at_startup |
| localization | locales and delegates | Flutter gen-l10n |
| resident | close-to-tray lifecycle | tray_manager + window_manager |
| sync | object sync and conflicts | ETag engine + WebDAV backend |

Sync only reads storage instances explicitly listed in its configuration. It
uses conditional ETag writes, persists tombstones and common bases, preserves
conflicts by default, and accepts an application-specific merge factory.

## Configuration and secrets

Schema version 2 stores named instances and adapter options. Dartloom-owned
storage categories are intentionally generic: `text`, `json`, and `database`.
Business-specific names such as “notes” do not appear in the framework catalog.

```yaml
capabilities:
  storage:
    instances:
      json:
        implementation: json_file
        options:
          path: dartloom/data.json
  sync:
    instances:
      default:
        implementation: etag_object
        stores: [storage.json]
        backend:
          implementation: webdav
          options:
            base_url: "${WEBDAV_URL}"
            username: "${WEBDAV_USERNAME}"
            password: "${WEBDAV_PASSWORD}"
```

`${NAME}` becomes a required `--dart-define=NAME=...`; secrets are never copied
into generated Dart source. Run `dartloom project update` once to migrate a
schema version 1 project. Managed files are overwritten directly.

## GitHub development and pub.dev release

```bash
dartloom source github  # hosted constraints plus Git/path overrides
dartloom source pub     # hosted pub.dev dependencies, no overrides
```

GitHub mode works before the packages are published. For pub.dev, publish
contracts first, then runtime/adapters, and finally the CLI. Every package has
hosted internal constraints and supports `dart pub publish --dry-run`; this
repository does not publish automatically.

## Build and installers

```bash
dartloom build windows
dartloom package windows exe
dartloom package windows zip
dartloom package windows msix
dartloom package linux deb
dartloom package linux rpm
```

Windows Setup.exe uses Inno Setup. Linux DEB/RPM packaging must run on Linux.
macOS DMG/PKG, iOS IPA, Android installer packaging, and web installers are not
currently supported. This installer limitation is separate from capability
platform support.

## Repository development

The repository root is orchestration-only; it is not an installable Dart
package. The CLI is `cli/dartloom_cli`, contracts and adapters are under
`packages`, and generated apps depend only on selected packages.
