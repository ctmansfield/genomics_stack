# Repository Upgrade Menu — Usage & Troubleshooting

This tool provides a **menu-driven** way to apply and roll back a set of quality-of-life upgrades to your Python repo.

## What it installs

1. **Linting/Formatting/Types (0001)**
   - `ruff`, `black`, `mypy`, `pre-commit`, `.editorconfig`
   - Configs: `pyproject.toml`, `mypy.ini`, `.pre-commit-config.yaml`

2. **Refactor Scaffold (0002)**
   - `tools/complexity_audit.sh` (Radon/Xenon)
   - `docs/refactor-playbook.md`

3. **Error Handling & Validation (0003)**
   - `lib/errors.py`, `support/logging.ini`, `support/config.py`
   - `docs/error-handling-and-validation.md`

4. **Dockerization (0004)**
   - `Dockerfile.app`, `.dockerignore`, `compose.override.yml`

5. **Testing (0005)**
   - `pytest.ini`, `tests/test_placeholder.py`

6. **CI/CD (0006)**
   - `.github/workflows/ci.yml`, `.github/workflows/release-docker.yml`

Backups + manifests live under `.genomics_patches/`.

---

## Quick Start

1. **Install the tool files**
   ```bash
   tar -xzf patch-0007-repo-upgrade-menu.tar.gz
   cd patch-0007-repo-upgrade-menu
   REPO_DIR=/root/genomics-stack bash install.sh
   ```

2. **Open the menu**
   ```bash
   /root/genomics-stack/tools/repo_upgrade_menu.sh
   ```

3. **Apply all patches at once (non-interactive)**
   ```bash
   /root/genomics-stack/tools/repo_upgrade_menu.sh --apply-all -y
   ```

4. **Roll back a specific patch**
   ```bash
   /root/genomics-stack/tools/repo_upgrade_menu.sh --rollback 0004 -y
   ```

5. **Roll back everything**
   ```bash
   /root/genomics-stack/tools/repo_upgrade_menu.sh --rollback all -y
   ```

6. **Verify**
   ```bash
   /root/genomics-stack/tools/repo_upgrade_menu.sh --verify
   ```

7. **Push to GitHub**
   ```bash
   /root/genomics-stack/tools/repo_upgrade_menu.sh --push
   ```

> The script commits after each patch application or rollback. Use `--push` to ship those commits to your default remote branch.

---

## Important Notes

- **Repo cleanliness:** The script requires a clean working tree. It can auto-commit any pending changes before proceeding.
- **Backups:** Before modifying a file, the original is saved to `.genomics_patches/backups/<patch_id>/`. A manifest of all touched files is stored at `.genomics_patches/applied/<patch_id>.files`.
- **Rollbacks:** On rollback, files are restored from backup; if a file was newly created, it is removed.
- **Idempotence:** Reapplying a patch overwrites files and re-records the manifest. If you’ve heavily customized configs, consider forking the configs before reapplying.

---

## Troubleshooting

### Pre-commit blocks my commits
- Run `pre-commit run --all-files` to see failures.
- Fix, then re-commit; or temporarily bypass: `git commit -m "...skip..." --no-verify` (not recommended).

### CI fails on GitHub
- **Lint/format:** Run `ruff check .` and `black .` locally and commit the changes.
- **Types:** `mypy` is configured leniently; adjust `mypy.ini` or add annotations.
- **Tests:** Run `pytest -q` locally. Use `pytest -k pattern -vv` for granular failures.
- **Postgres in CI:** The workflow spins up `postgres:16`; check DSN usage in tests or skip DB-dependent tests initially.

### Docker image builds too large
- Ensure caches and data dirs are in `.dockerignore` (already included).
- Prefer installing from wheels (the Dockerfile does this via multi-stage).

### Permission errors writing `.genomics_patches/`
- Run the script as a user with write access to the repo (often root in your environment).
- Check disk space and directory permissions.

### Git push fails (auth/remote)
- Verify `git remote -v` is set and you have credentials (SSH or PAT).
- Push manually:
  ```bash
  cd /root/genomics-stack
  git push origin $(git rev-parse --abbrev-ref HEAD)
  ```

### I need to customize generated configs
- Edit the files after application and commit. If you reapply a patch later, it may overwrite your customizations—consider copying your changes to a separate config or adjusting the script to merge.

---

## Uninstall

To remove all applied changes:
```bash
/root/genomics-stack/tools/repo_upgrade_menu.sh --rollback all -y
```
Then remove the script and state:
```bash
rm -rf /root/genomics-stack/.genomics_patches
rm -f  /root/genomics-stack/tools/repo_upgrade_menu.sh
```

---

## FAQ

**Q: Does rollback restore my code exactly?**
A: Yes—only for files touched by the patch and captured in the manifest. Unrelated files are untouched.

**Q: Will it modify my Git history?**
A: The script creates new commits for apply/rollback. It won’t rewrite existing commits.

**Q: Can I run this on a different repo path?**
A: Yes: `REPO_DIR=/path/to/repo tools/repo_upgrade_menu.sh` or `--repo /path/to/repo`.
