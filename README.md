# Master's Research Slides

Marp-based slide decks for two research proposals on blockchain node security.

## Decks

| Folder | Topic |
|--------|-------|
| `security-wasm-filtering/` | WASM Envoy filters for Ethereum API security (service mesh) |
| `ebpf-host-profiling/` | eBPF-based host-level behavioral profiling for blockchain nodes |

## Requirements

- [marp-cli](https://github.com/marp-team/marp-cli) — `npm install -g @marp-team/marp-cli` (or `just setup`)
- [just](https://github.com/casey/just) — command runner

## Usage

```sh
just            # List available recipes
just serve      # Live-reload server at http://localhost:8080
just build      # Build HTML + PDF for all decks
just html       # Build HTML only (faster, no browser needed)
just clean      # Remove generated files
```

Override port: `PORT=3000 just serve`

## Structure

```
slides/
├── justfile               # Build/serve commands
├── theme/style.css        # Shared Marp theme
├── security-wasm-filtering/
│   └── slides.md
└── ebpf-host-profiling/
    └── slides.md
```
