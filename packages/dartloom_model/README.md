# dartloom_model

Provider-independent `GenerationModel`, `EmbeddingModel`, `ModelRequest`, and
serializable `ModelConnection` contracts. Credentials belong in an application's
secure settings store, never in `ModelConnection` or synchronized data.

Native adapters live in `dartloom_model_io`. Application-specific prompts and
interpretation of model output remain in the consuming application's features.
