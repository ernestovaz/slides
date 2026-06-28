# Marp slide deck build system
# Shared between both research idea presentations
# Requires: marp-cli (npm install -g @marp-team/marp-cli)

theme_dir := "theme"
theme_css := theme_dir / "style.css"
port := env("PORT", "8080")

# Default: show available commands
default:
    @just --list

# ─── Serve ───────────────────────────────────────────────────────

# Serve all presentations with live-reload (browse at localhost:8080)
serve:
    marp -I . \
        --theme {{theme_css}} \
        --html \
        --watch \
        --server \
        --server-port {{port}}

# ─── Build ───────────────────────────────────────────────────────

# Build all slide decks (HTML + PDF)
build:
    marp -I . \
        --theme {{theme_css}} \
        --html
    marp -I . \
        --theme {{theme_css}} \
        --html \
        --pdf

# Build HTML only (faster, no PDF/browser dependency)
html:
    marp -I . \
        --theme {{theme_css}} \
        --html

# ─── Utilities ───────────────────────────────────────────────────

# Clean generated files
clean:
    rm -f security-wasm-filtering/slides.html security-wasm-filtering/slides.pdf
    rm -f ebpf-host-profiling/slides.html ebpf-host-profiling/slides.pdf

# Install marp-cli if not present
setup:
    npm install -g @marp-team/marp-cli
