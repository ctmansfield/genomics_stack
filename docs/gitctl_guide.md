# Genomics Stack – Git & Release Guide

This is a quick “how do I do it again?” for infrequent use.

---

## TL;DR cheat sheet

    # set identity (once per repo)
    bash scripts/dev/gitctl.sh set-identity "NAS Admin" "nas-admin@local"

    # save work
    bash scripts/dev/gitctl.sh save -m "short message"

    # push to local NAS remote
    bash scripts/dev/gitctl.sh push

    # make a release archive + tag, keep newest 10 archives
    bash scripts/dev/gitctl.sh release -m "checkpoint" -k 10
    git push --tags origin

    # list releases and verify the latest
    bash scripts/dev/gitctl.sh list-releases
    bash scripts/dev/gitctl.sh verify-release /mnt/nas_storage/genomics-stack/backups/<file>.tgz

    # explore an old tag safely (no changes to working tree)
    bash scripts/dev/gitctl.sh worktree <tag> /tmp/gstack_<tag>

    # hard rollback current branch to a ref (asks for confirmation; creates a safety tag first)
    bash scripts/dev/gitctl.sh rollback <ref>

---

## Initial setup (first time only)

    git init
    bash scripts/dev/gitctl.sh set-identity "NAS Admin" "nas-admin@local"
    bash scripts/dev/gitctl.sh set-remote /mnt/nas_storage/genomics-stack/git/genomics-stack.git
    git branch -M main
    git add -A && git commit -m "baseline"
    git push -u origin main

If the bare remote isn’t created yet:

    mkdir -p /mnt/nas_storage/genomics-stack/git
    git init --bare /mnt/nas_storage/genomics-stack/git/genomics-stack.git
    git --git-dir=/mnt/nas_storage/genomics-stack/git/genomics-stack.git symbolic-ref HEAD refs/heads/main

---

## Day-to-day

- **Check status**  
  `bash scripts/dev/gitctl.sh status`

- **Save changes**  
  `bash scripts/dev/gitctl.sh save -m "what changed"`

- **Push / Pull**  
  `bash scripts/dev/gitctl.sh push`  
  `bash scripts/dev/gitctl.sh pull`

- **Quick backup (not tagged)**  
  `bash scripts/dev/gitctl.sh backup`  
  → writes to `/mnt/nas_storage/genomics-stack/backups/…`

---

## Making a release

1) Tag + archive HEAD into NAS backups:  
   `bash scripts/dev/gitctl.sh release -m "why this release" -k 10`

2) Push the tag to the remote repo:  
   `git push --tags origin`

3) Verify checksum (optional):  
   `bash scripts/dev/gitctl.sh list-releases`  
   `bash scripts/dev/gitctl.sh verify-release /mnt/nas_storage/genomics-stack/backups/<file>.tgz`

**Where it goes:**  
`/mnt/nas_storage/genomics-stack/backups/genomics-stack_<tag>_<shortsha>.tgz`  
`/mnt/nas_storage/genomics-stack/backups/genomics-stack_<tag>_<shortsha>.tgz.sha256`

---

## Rolling back / inspecting old versions

- **Safe inspection** (no changes to current tree):

      bash scripts/dev/gitctl.sh worktree <tag> /tmp/gstack_<tag>
      # when done:
      git worktree remove /tmp/gstack_<tag>

- **Detached checkout** (read-only):

      bash scripts/dev/gitctl.sh checkout <tag>

- **Hard rollback current branch** (destructive; confirmation required):

      bash scripts/dev/gitctl.sh rollback <ref>

  The script creates a safety tag first (e.g., `safety-rollback-YYYYmmdd-HHMMSSZ`) so you can undo.

- **Extract a release archive (no .git)**:

      bash scripts/dev/gitctl.sh extract /mnt/nas_storage/genomics-stack/backups/<file>.tgz /tmp/restore

---

## Remotes & identity

    bash scripts/dev/gitctl.sh set-identity "NAS Admin" "nas-admin@local"
    bash scripts/dev/gitctl.sh set-remote /mnt/nas_storage/genomics-stack/git/genomics-stack.git

---

## Troubleshooting

- **“Command not found”**: always run with `bash …` (works even on `noexec` mounts).  
- **“Author identity unknown”**: run `set-identity`.  
- **CRLF/line endings**: `bash scripts/dev/gitctl.sh doctor`.  
- **Merge conflicts**: `bash scripts/dev/gitctl.sh pull` (rebase), resolve, then `save` and `push`.

---

## Optional alias

    echo 'alias gctl="bash $HOME/genomics-stack/scripts/dev/gitctl.sh"' >> ~/.bashrc
    . ~/.bashrc
    gctl status

---

## Tagging scheme

Default tag is `rel-YYYYmmdd-HHMMSSZ`. You can supply your own with `-t v0.2.0`.
