# dartloom_messaging_lan

TLS/LAN transport adapter for the generic
[`dartloom_messaging`](../dartloom_messaging) contracts in the
[Dartloom](https://github.com/wkzMagician/dartloom) project.

The adapter frames already encrypted Packets and encrypted attachment blobs,
waits for blob acknowledgements, and never interprets application payloads.
