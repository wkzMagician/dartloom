# Dartloom External Input

dartloom_external_input defines the platform-neutral contract for content
received through sharing, Open With, intents, and deep links.

Applications compose a platform adapter and pass ExternalInputService to their
feature code. The contract deliberately does not model any application
workflow, destination, or device.
