# Contributing to mermaid.nvim 🧜

Thanks for your interest in contributing! This document outlines how to get started.

## Project Structure

```
mermaid.nvim/
├── lua/mermaid/
│   ├── init.lua      # Plugin entry point, config defaults
│   ├── format.lua    # Built-in Mermaid diagram formatter
│   ├── lint.lua      # Diagnostics via mermaid-cli
│   ├── preview.lua   # Preview orchestration (browser, autocommands)
│   └── server.lua    # Built-in Lua HTTP server with SSE
├── plugin/
│   └── mermaid.lua   # User commands (:MermaidFormat, :MermaidPreview, etc.)
├── ftdetect/
│   └── mermaid.lua   # Filetype detection (.mmd, .mermaid)
├── static/
│   ├── index.html    # Preview page template
│   ├── css/preview.css
│   └── js/preview.js # Client-side rendering + toolbar
├── tests/            # Plenary test specs
├── doc/
│   └── mermaid.txt   # Vim help file
└── .github/
    ├── workflows/    # CI configuration
    └── ISSUE_TEMPLATE/
```

## Development Setup

1. Clone the repo into your Neovim plugin path.
2. Make changes on a dedicated branch created from the latest `main`.
3. Reload with `:luafile %` or restart Neovim.
4. Run tests:

```bash
make test
# or
nvim --headless -u tests/minimal_init.lua \\
  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"
```

## Development Workflow

The project uses a single-main workflow. There is no `develop` branch.

```text
main → feature/fix/refactor/docs/ci branch → Pull Request → main
```

1. Start from an up-to-date `main` branch:

   ```bash
   git switch main
   git pull --ff-only origin main
   ```

2. Create a dedicated branch from `main`:

   ```bash
   git switch -c fix/short-description
   # or: feat/short-description
   ```

3. Implement the change and add or update tests.
4. Update `doc/mermaid.txt` if adding or changing commands or configuration.
5. Run the local checks listed below.
6. Push the branch and open a Pull Request targeting `main`.
7. Address review feedback and keep the branch up to date with `main` when needed.
8. Merge only after the required checks and review have passed.

### Branch naming

Use a short, descriptive branch name with one of these prefixes:

- `feat/` — new feature
- `fix/` — bug fix
- `refactor/` — code restructure
- `docs/` — documentation only
- `ci/` — CI or workflow changes
- `test/` — test-only changes

## Code Style

- Use 2-space indentation in Lua files.
- Follow Neovim Lua conventions (snake_case functions, PascalCase modules).
- Document public API functions with comments.
- Keep the built-in HTTP server minimal — no external dependencies.
- All new features should have corresponding tests.

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — new feature
- `fix:` — bug fix
- `refactor:` — code restructure
- `test:` — test additions/updates
- `docs:` — documentation only
- `ci:` — CI/workflow changes

## Pull Request Checklist

- [ ] Branch is based on the latest `main`.
- [ ] PR targets `main`.
- [ ] Tests pass: `make test`.
- [ ] New tests added for new behavior.
- [ ] Documentation updated if applicable.
- [ ] No new `vim.notify` noise in tests (mock if needed).
- [ ] PR description explains the change and verification.

## Questions?

Open an issue or start a discussion — we're happy to help!
