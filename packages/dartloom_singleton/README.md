# dartloom_singleton

Stable desktop single-instance contract with an in-memory test
implementation. Platform behavior (the actual process lock and
inter-process argument delivery) is provided by adapters, e.g.
`dartloom_singleton_filelock`.

Applications normally select implementations through `dartloom cap`.