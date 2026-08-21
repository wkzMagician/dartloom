# dartloom_pairing

Generic device pairing capability for Dartloom. It provides:

- stable X25519 device identity generation through an injected secure-store
  contract;
- portable `actent://pair/v1/...` invitations with a ten-minute default
  lifetime;
- device metadata, short-code confirmation and HMAC proof contracts;
- injected relay control handshake contracts for QR/paste fallback;
- temporary TLS request/response pairing with certificate pinning;
- short-lived DNS-SD/mDNS discovery advertisements;
- QR presenter/scanner contracts and Flutter adapters in `qr_adapters.dart`.

The acceptance/confirmation message schema is published at
`schema/pairing_messages.schema.json`.

The package does not know about Actent Work Catalogs or business message
delivery. Actent receives only the verified pairing result and persists its
own Device endpoint.

# iOS local-network permissions

LAN/mDNS pairing on iOS requires these entries in the application-owned
`ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Dartloom uses the local network to pair nearby devices.</string>
<key>NSBonjourServices</key>
<array>
  <string>_actent._tcp</string>
</array>
```

Browser builds must use `PairingRelayHandshake` (WebSocket/HTTP relay); the
LAN socket and mDNS classes are native-only.
