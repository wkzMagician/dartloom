# dartloom_pairing

Generic device pairing capability for Dartloom. It provides:

- stable X25519 device identity generation through an injected secure-store
  contract;
- portable `pigeon://pair/v1/...` invitations with a ten-minute default
  lifetime;
- device metadata, short-code confirmation and HMAC proof contracts;
- injected relay control handshake contracts for QR/paste fallback;
- temporary TLS request/response pairing with certificate pinning;
- short-lived DNS-SD/mDNS discovery advertisements;
- QR presenter/scanner contracts and Flutter adapters in `qr_adapters.dart`.

The acceptance/confirmation message schema is published at
`schema/pairing_messages.schema.json`.

The package does not know about Pigeon Work Catalogs or business message
delivery. Pigeon receives only the verified pairing result and persists its
own Device endpoint.


