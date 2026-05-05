# agentic_interop

Internal AI Copilot for InterSystems IRIS for Health. A configuration-driven chatbot that helps developers and integration engineers CRUD Productions, CRUD Transformations, and Test HL7/FHIR data inside any IRIS for Health namespace they have access to. Built entirely on the InterSystems %AI Framework.

## Status

Pre-alpha. See [docs/PLAN.md](docs/PLAN.md) for architecture decisions and [docs/MIGRATION.md](docs/MIGRATION.md) for the class-by-class build map.

## Requirements

- InterSystems IRIS for Health 2026.2 or newer
- IPM (ZPM) installed in the target namespace
- An LLM API key you control. Anthropic direct is the reference dev provider; Bedrock and Azure OpenAI are configurable but see [docs/PLAN.md](docs/PLAN.md) "Provider strategy" for the current Bedrock + tool-call hang status.

## Install

```bash
git clone https://github.com/dfrancoisc/agentic_interop.git
cd agentic_interop
```

In an IRIS terminal, switch to the namespace where you want the copilot installed (any namespace you have privileges in — HSCUSTOM, USER, a custom one):

```objectscript
ZN "<your-namespace>"
zpm "load /path/to/agentic_interop"
```

The module installs all classes, web apps, REST endpoints, and vector tables into the namespace where you ran `zpm load`. To install in multiple namespaces, run the command once per namespace.

## After install

1. Open the admin UI at `http://<host>:<web-port>/agentic/admin/`.
2. Add an LLM Provider — paste your API key. The key is stored in the IRIS Secured Wallet, never in plaintext.
3. Click Save and test. The semaphore goes green when the connection works.
4. The chatbot button appears in the Angular host page when a user is logged in. The active namespace is shown at the top of the chatbot window.

## Development

See [docs/PLAN.md](docs/PLAN.md) "Build phases" for the current phase and what is unlocked next.

The runtime container used for local development is `iris-agentic` on ports 21972 (super) / 22773 (web) / 23773 (xDBC), separate from any other IRIS containers on the host. Login `_SYSTEM` / `Agentic1!`.

## License

TBD.
