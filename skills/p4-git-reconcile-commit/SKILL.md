---
name: p4-git-reconcile-commit
description: Reconciles a Git commit with P4 Default changelist. Follows a strict interactive workflow to analyze and move files, then generates a summary report.
---

# P4-Git Reconcile Commit

This skill helps you isolate files belonging to a Git commit from the P4 `default` changelist.

## Standard Workflow (Mandatory)

To ensure a consistent experience, the agent MUST follow these steps:

1.  **Request Input**: Ask the user for:
    - **Git Commit Hash**
    - **Target P4 Changelist ID**
    - **Output Directory Path** for the report.
2.  **Analysis**: Run `reconcile_and_move.cjs <hash> <cl> --output-dir <path>`.
3.  **Presentation & Confirmation**: Show the matched files and ask for confirmation before moving.
4.  **Execution**: Run the `p4 reopen` command if confirmed.

## Tools & Scripts

### Reconcile Script
```bash
node scripts/reconcile_and_move.cjs <hash> <cl> --output-dir <path>
```
