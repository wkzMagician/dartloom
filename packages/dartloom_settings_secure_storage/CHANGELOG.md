## 0.1.1

- Migrate existing iOS Keychain entries from the previous accessibility
  policy before retrying writes, avoiding `errSecDuplicateItem` during app
  startup after upgrading to `first_unlock`.

## 0.1.0 - Initial production adapter release.
