# dartloom_messaging

Generic device-to-device messaging contracts for the
[Dartloom](https://github.com/wkzMagician/dartloom) project.

The public entry point `dartloom_messaging.dart` exports:

- versioned Packet validation, memory connection and deduplication contracts;
- X25519 + HKDF-SHA-256 + AES-256-GCM Packet crypto;
- transport-neutral Packet routing and bounded relay retry policy;
- independently authenticated attachment chunks;
- re-openable sources, persistent sink contracts and resumable sessions;
- binary encrypted chunks, Blob/BlobRef contracts and the v2
  offer/resume/chunkRef/commit protocol.

Concrete transports are separate packages:

- `dartloom_messaging_ntfy` implements ntfy HTTP/WebSocket and native blobs;
- `dartloom_messaging_lan` implements pinned TLS/LAN Packet delivery.

The Packet JSON Schema is published at `schema/packet.schema.json`.

This package deliberately does not know about Actent Work, Inbox, Catalog or
UI protocols. Applications carry those values as encrypted opaque payloads and
provide their own durable storage implementations.

