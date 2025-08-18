# Lint protocol (must-follow) — lint-baseline-v1

- When proposing Python code, ensure it passes **Ruff** with `select = ["E","F","W","I","UP"]` and line-length 100, and is formatted with `ruff --config pyproject.ruff.toml format .`.
- Prefer auto-fixes; if a rule needs waiving, add a brief comment and suggest an ADR note.
- For Bash, ensure scripts pass **shellcheck** (severity ≥ warning) and are formatted with **shfmt** (indent=2, `-ci`).
- Include `make format` + `make lint` in your steps and show any edits required to satisfy the hooks.
