# dartloom_pairing

Generic device pairing capability for
[Dartloom](https://github.com/wkzMagician/dartloom). It supplies the identity,
invitation, verification, relay-handshake, and LAN pairing contracts used by
Dartloom applications. It provides:

- stable X25519 device identity generation through an injected secure-store
  contract;
- portable v2 application-defined-scheme invitations with a ten-minute default
  lifetime;
- device metadata, short-code confirmation and HMAC proof contracts;
- injected relay control handshake contracts with separate control and
  native-attachment blob topics, plus QR/paste fallback;
- temporary TLS request/response pairing with certificate pinning;
- short-lived DNS-SD/mDNS discovery advertisements;
- QR presenter/scanner contracts and Flutter adapters in `qr_adapters.dart`.

The invitation/acceptance/confirmation message schema is published at
`schema/pairing_messages.schema.json`. Version 2 is intentionally incompatible
with version 1.

The package does not know about application Work Catalogs or business-message
delivery. The application receives only a verified pairing result and persists
its own device endpoint.

# iOS local-network permissions

LAN/mDNS pairing on iOS requires these entries in the application-owned
`ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Dartloom uses the local network to pair nearby devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_example._tcp</string>
</array>
```

Browser builds must use `PairingRelayHandshake` (WebSocket/HTTP relay); the
LAN socket and mDNS classes are native-only.
