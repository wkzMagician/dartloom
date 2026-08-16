# dartloom_storage_indexeddb

Browser `ObjectStore` adapter backed by one IndexedDB database per namespace.
Objects survive reloads and changes are broadcast to other tabs through
`BroadcastChannel`. VM execution uses an explicitly test-only in-memory
fallback because IndexedDB is a browser capability.
