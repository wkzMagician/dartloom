# Changelog

## 0.3.0

- Removed the `hierarchical` option from `FileObjectStore`. Directory-backed
  storage always accepts hierarchical keys (e.g. `__dartloom_journal/v1/...`)
  so it stays compatible with `JournaledObjectStore`'s metadata keys.

## 0.2.0

- Renamed `FileDirectoryStore` to `FileObjectStore` and removed sync metadata.
