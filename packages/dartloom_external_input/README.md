# Dartloom External Input

`dartloom_external_input` is the [Dartloom](https://github.com/wkzMagician/dartloom)
contract for content received through sharing, Open With, intents, deep links,
and an explicitly requested clipboard read. Applications compose a platform
adapter and pass `ExternalInputService` to their feature code.

`ClipboardExternalInputReader` deliberately does not choose when to inspect the
clipboard; that remains an application interaction policy. The contract does
not model any application workflow, destination, or device.
