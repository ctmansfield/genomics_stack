# ShellCheck fixes patch (v3)

This bundle makes minimal, safe edits to address the ShellCheck findings you shared.

## How to use

```bash
tar -xzf shellcheck_fixes_patch_v3.tar.gz
cd shellcheck_fixes_patch_v3
./apply.sh /path/to/your/repo

# then from your repo root:
pre-commit run -a
```

Backups of each modified file are stored under `.patch_backups/<UTC timestamp>/` in your repo.
