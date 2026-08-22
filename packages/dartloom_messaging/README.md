# dartloom_messaging

Generic device-to-device messaging capability for Dartloom. The public entry
point `dartloom_messaging.dart` exports:

- versioned `Packet`, validation, memory connection and deduplication contracts;
- X25519 + HKDF-SHA-256 + AES-256-GCM packet crypto;
- length-prefixed TLS/LAN transport and ntfy HTTP/WebSocket adapters;
- bounded relay retry policy with `Retry-After` support;
- independently authenticated attachment chunks and 24-hour incomplete
  transfer cleanup.
- re-openable attachment sources, persistent sink contracts, missing-range
  discovery, and resumable chunk send/receive sessions.

The packet contract schema is published at `schema/packet.schema.json`.

This package deliberately does not know about Pigeon Work, Inbox, Catalog or
UI protocols. Those values are carried as encrypted opaque payload bytes by
the generic Packet transport.

Attachment streaming is exposed through `AttachmentSource` and
`AttachmentSink`. Applications provide storage appropriate to their target;
the capability only defines the manifest, encrypted chunk, resume, and atomic
commit contracts.

