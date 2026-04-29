# Documentation

## Start here

| Document | Description |
|----------|-------------|
| [Overview](overview.md) | System architecture, auth flow diagrams, Keycloak client mapping, token storage model |
| [PoC Guide](poc-guide.md) | Step-by-step walkthrough of the Vue PoC app (sign-in, token exchange, simulation) |
| [Troubleshooting](troubleshooting.md) | Common errors and how to fix them |

## SDK Reference

| Document | Description |
|----------|-------------|
| [Getting Started](getting-started.md) | SDK installation, initialization, making API calls, providing tokens |
| [Writing Plugins](writing-plugins.md) | How to create custom MorphPlugin implementations (auth, storage, or custom) |
| [Configuration](configuration.md) | Full reference for every config field (providers, contexts, hosts, variables) |
| [API Reference](api-reference.md) | Complete public API: MorphClient, HostClient, AuthHandle, types, errors |
| [Token Lifecycle](token-lifecycle.md) | Token resolution algorithm, refresh, exchange, recovery, session monitoring |
| [Platform Adapters](platform-adapters.md) | StorageProvider (via plugins) and NetworkDelegate interfaces |
| [Architecture](architecture.md) | Internal design: module structure, HTTP pipeline, dependency graph |
| [Dart parity](dart-parity.md) | Dart/Flutter SDK roadmap, `packages/dart/morph_core` scaffold ([issue #1](https://github.com/burgan-tech/morph-api-client/issues/1)) |

| Document | Description |
|----------|-------------|
| [poc/google-setup.md](poc/google-setup.md) | Google Cloud Console setup for the external IdP integration |
| [poc/simulation.md](poc/simulation.md) | How the simulation panel works (`poc-simulation.json` schema) |
| [poc/test-scenarios.md](poc/test-scenarios.md) | Nine test scenarios with curl recipes for all OAuth flows |
