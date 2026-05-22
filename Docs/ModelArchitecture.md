# Model Architecture

Swoosh has one canonical model registry: `SwooshModels`.

## Ownership

- `ModelDefaults` owns default provider IDs and model IDs.
- `CloudCatalog` lists only cloud routes that have a wired provider adapter.
- `ModelCatalog.curatedModels` lists local installable models.
- `UnifiedModelCatalog` joins cloud and local entries, exposes `interactive` for the chat picker, and resolves picker IDs into `(providerID, modelID)`.

Provider modules execute requests. They do not own product defaults.

## Request Flow

1. UI stores a catalog ID in `AgentShellModel.selectedModelID`.
2. `UnifiedModelCatalog.route(forCatalogID:)` resolves it before chat submission.
3. `ChatRequest` carries optional `providerID` and `model`.
4. `SwooshAPI` maps that into `AgentRequest`.
5. `AgentKernel` passes `model` and `providerID` through `ModelCompletionRequest`.
6. `SwooshProviderBridge` passes both fields into `ModelRequest`.
7. `ProviderRouter` filters by explicit `providerID`; if no provider is set, it uses normal route priority.

`nil` provider/model means Auto.

## Current Defaults

- Auto picker default: `auto`
- ChatGPT bridge: `codex:auto`
- OpenAI API: `openai:gpt-5.5`
- OpenAI coding API: `openai:gpt-5.2-codex`
- OpenRouter API: `openrouter:openai/gpt-5.5`
- Mac Swift local default: `mlx-local:mlx-community/gemma-4-e4b-it-4bit`
- Mac Swift local fallback: `mlx-local:mlx-community/gemma-4-e2b-it-4bit`
- Local Mac OpenAI-compatible: `local-openai:gemma4:e4b`
- Local Mac tight-memory fallback: `local-openai:gemma4:e2b`
- iOS LiteRT fallback: `litert-local:gemma-4-E4B-it`
- Apple Foundation Models: `apple-foundation:apple-on-device`
- Phone tool router: `local-openai:functiongemma:270m`

## Local Runtime Policy

MLX Swift is the default Mac-native local route on Apple Silicon. `SwooshMLX` loads local model directories from `~/.swoosh/models` and MLX Hub IDs such as `mlx-community/gemma-4-e4b-it-4bit` through `mlx-swift-lm`.

Ollama / OpenAI-compatible servers remain the optional Mac local server route. The router excludes `functiongemma:*` from primary chat autodiscovery because it is a tool-routing model, not a primary assistant.

LiteRT is the iOS offline fallback path. Apple Foundation Models are a separate on-device provider and remain opt-in through `SWOOSH_FOUNDATION_MODEL=1`.

## Quantization

Swoosh does not run `Dexploarer/bitsandbytes` or any Python bitsandbytes path. Quantized models enter through supported runtime artifacts:

- Ollama tags for Mac local GGUF-style serving
- LiteRT `.litertlm` bundles for iOS fallback
- MLX-compatible Hugging Face Hub weights through `mlx-swift-lm`

Do not add a bitsandbytes dependency unless there is a separate Python inference runtime.
