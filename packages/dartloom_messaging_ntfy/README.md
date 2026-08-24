# dartloom_messaging_ntfy

ntfy relay and native-attachment adapter for the generic
[`dartloom_messaging`](../dartloom_messaging) contracts in the
[Dartloom](https://github.com/wkzMagician/dartloom) project.

The adapter accepts a raw ntfy access token, publishes encrypted Packet JSON
as `text/plain`, catches up cached Packets through authenticated HTTP polling,
and stores already encrypted binary chunks as native ntfy attachments.
