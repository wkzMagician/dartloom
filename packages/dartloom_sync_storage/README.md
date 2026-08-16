# dartloom_sync_storage

Profile-scoped storage, durable mutation journaling, mutation observation,
conditional local writes, profile
metadata, and reconciliation state adapters for Dartloom Sync.

`ObjectStoreLocalReplicaFactory` requires separate `objects` and `metadata`
stores. The metadata store contains the durable journal and must not be inside
the replicated business-data root.
