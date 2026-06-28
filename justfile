# Marp slide deck build system
# Requires: marp-cli (npm install -g @marp-team/marp-cli) — see `just setup`
# Shared options live in .marprc.yml.

port := env("PORT", "8080")

# Default: show available commands
default:
    @just --list

# ─── Serve ───────────────────────────────────────────────────────

# Serve all presentations with live-reload (browse at localhost:8080)
serve:
    marp -I . --watch --server --server-port {​{port}}

# ─── Build ───────────────────────────────────────────────────────

# Build HTML + PDF for all decks (and the index)
build: html pdf

# Build HTML only (fast, no browser needed)
html:
    marp index.md '**/slides.md'

# Build PDF (requires Chromium-based browser installed)
pdf:
    marp index.md '**/slides.md' --pdf

# ─── Utilities ───────────────────────────────────────────────────

# Remove generated files
clean:
    find . \( -name 'slides.html' -o -name 'slides.pdf' -o -name 'index.html' -o -name 'index.pdf' \) \
        -not -path './node_modules/*' -delete

# Install marp-cli if not present
setup:
    npm install -g @marp-team/marp-cli
