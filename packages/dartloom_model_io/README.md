# dartloom_model_io

Native adapters for `dartloom_model`:

- `ApiGenerationModel`: configurable OpenAI-compatible `/chat/completions`.
- `ApiEmbeddingModel`: independent OpenAI-compatible `/embeddings`, with index,
  count, dimension and finite-value validation.
- `OllamaGenerationModel`: local `/api/chat` JSON generation.
- `OllamaEmbeddingModel`: local `/api/embed`, batched and validated.
- `CodexSubscriptionModel`: desktop `codex exec --json` with existing CLI login.
- `ModelAccountAuth`: native ChatGPT device authorization and refresh, plus
  OpenRouter headless S256 PKCE authorization.
- `ChatGptGenerationModel`: authenticated Codex Responses streaming, including
  completion validation. It works without a desktop CLI.

Applications supply the endpoint, installed model name, and secure API credential.
The application owns login UI, cancellation, refresh scheduling and secure token
persistence. This package does not download models or persist credentials.
HTTP clients honor environment proxies and Windows manual system proxies;
loopback model connections always remain direct.
Subscription access requires a compatible installed Codex CLI and an eligible
account logged in using `codex login`; a ChatGPT subscription is not an API key.
The CLI runs in a temporary directory with read-only sandboxing, receiving only
the supplied prompt. API environment credentials are removed for this adapter.

References: https://developers.openai.com/codex/noninteractive and
https://developers.openai.com/codex/auth .
OpenRouter PKCE: https://openrouter.ai/docs/guides/overview/auth/oauth .
