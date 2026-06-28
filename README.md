# Slides

[Marp](https://marp.app)-based slide decks. Each subdirectory contains one deck
(`slides.md`). The root `index.md` is the landing page linking to every deck.
Shared theme lives in `theme/style.css`; shared marp options in `.marprc.yml`.

Published automatically to GitHub Pages on push to `main`.

## Requirements

- [marp-cli](https://github.com/marp-team/marp-cli) — `npm install -g @marp-team/marp-cli` (or `just setup`)
- [just](https://github.com/casey/just) — command runner
- A Chromium-based browser is needed for `just pdf` / `just build`

## Local usage

```sh
just            # list available recipes
just serve      # live-reload server at http://localhost:8080
just html       # build HTML only (fast, no browser needed)
just pdf        # build PDF
just build      # build HTML + PDF
just clean      # remove generated files
```

Override port: `PORT=3000 just serve`

## Adding a new deck

1. Create a new directory at the repo root.
2. Add a `slides.md` with Marp frontmatter:
   ```yaml
   ---
   marp: true
   size: 16:9
   paginate: true
   html: true
   ---
   ```
3. Add a link to it in `index.md` (the landing page).
4. Commit and push — CI will build it and publish to GitHub Pages.

## CI / Publishing

The `Build & Deploy Slides` workflow (`.github/workflows/deploy.yml`):

- Builds HTML + PDF for every `**/slides.md` on every push and PR.
- On `main`, deploys the output to GitHub Pages with an auto-generated index
  listing every discovered deck.
- On PRs, attaches the rendered output as a downloadable artifact.

**One-time setup in the GitHub repo:** Settings → Pages → Source: *GitHub Actions*.

## Repository layout

```
.
├── .marprc.yml              # shared marp-cli options (theme, html)
├── justfile                 # build/serve commands
├── index.md                 # landing page (linked to from GitHub Pages root)
├── theme/style.css          # shared Marp theme
├── <deck-name>/slides.md    # one folder per deck
└── .github/workflows/       # CI: build + deploy to GitHub Pages
```
