# dartloom_storage_file

Binary-safe directory replica for Dartloom.

The application must resolve and pass both absolute paths:

- `root` is the application-owned business-data directory.
- `metadataRoot` is a separate application-support directory for the intent
  journal and trusted observation state.

Dartloom never chooses a business directory and never places metadata inside
`root`. Authorized application, migration, and conflict-resolution mutations
create durable intents. Remote recovery and ordinary filesystem observation do
not create upload or delete intent.
