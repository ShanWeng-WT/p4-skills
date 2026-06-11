---
name: p4-git-hybrid
description: Sets up and manages a Git repository on top of a Perforce workspace for hybrid workflow. Use when the user wants to use Git's local branching and staging features while maintaining Perforce as the primary source control system.
---

# P4-Git Hybrid Workflow

This skill facilitates a "Git on top of P4" development model, allowing developers to use Git's powerful local branching, staging, and atomic commits without disrupting the team's Perforce workflow.

## When to Use

- When a developer prefers Git's local development flow (branches, stashes, fine-grained commits).
- When you want to isolate experimental changes in local Git branches.
- When you want to maintain a local history of changes before submitting a final version to Perforce.

## Setup Workflow

1.  **Initialize Git**: Execute `git init` in the Perforce workspace root.
2.  **Configure Ignore Files**:
    - Use the appropriate template (e.g., [assets/unity.gitignore](assets/unity.gitignore) for Unity projects).
    - Ensure P4 metadata (`p4config.txt`, `.p4ignore`) is ignored in `.gitignore`.
    - Create a `.p4ignore` file (template: [assets/p4ignore.txt](assets/p4ignore.txt)) and add `.git/` and `.gitignore` to it.
3.  **Surgical Initial Commit**:
    - Run `git add .gitignore .p4ignore` (use `-f` if they are cross-ignored).
    - Run `git commit -m "chore: setup hybrid workflow ignore files"`.
    - This ensures your ignore rules are locked in before the massive baseline add.
4.  **Enable P4IGNORE**: Run `p4 set P4IGNORE=.p4ignore` to make Perforce respect the ignore file.
5.  **Baseline Commit & Dev Branch**:
    - Run `git add .` and `git commit -m "Initial baseline commit from Perforce"`.
    - **CRITICAL**: Create a development branch immediately: `git checkout -b dev`.
 This keeps your `master` branch clean and in sync with the P4 server state.

## Daily Workflow Guidance

### 1. Syncing from Perforce (Getting Updates)
Before syncing, ensure your Git working tree is clean.
```bash
git add .
git commit -m "Save state before sync"
# OR
git stash
```
Then sync from P4:
```bash
p4 sync
```
After syncing, you can see what changed in Git and handle any conflicts locally.

### 2. Local Development
Use Git as usual:
- `git checkout -b feature/my-new-task`
- `git commit -m "Atomic change part 1"`
- `git commit -m "Atomic change part 2"`

### 3. Submitting to Perforce
When the feature is ready and tested:
1. Merge your feature branch back to your "main" Git branch (which tracks P4).
2. Open files for edit in P4: `p4 edit ...` (or use `p4 reconcile` to detect changes).
3. Submit to P4: `p4 submit -d "Feature description"`
4. Commit the submit metadata back to Git if desired.

## Reference

- For detailed hybrid workflow strategies, see [references/workflow.md](references/workflow.md).
