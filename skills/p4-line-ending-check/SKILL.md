---
name: p4-line-ending-check
description: Audits P4 pending changelists for line-ending differences. Requires a mandatory interactive prompt to gather CL IDs and user-defined output directory before execution.
---

# P4 Line Ending Check

This skill identifies files in your Perforce pending changelists that appear modified but actually only have line-ending differences.

## Mandatory Rules

- **Always Use `ask_user`**: You MUST use the `ask_user` tool to obtain the **Output Directory Path** from the user. Do NOT use a default path or assume the current directory.
- **Path Validation**: Ensure the provided path is a valid directory on the local file system.
- **Mandatory Revert Confirmation**: After presenting the results, if there are files identified as "Safe to Revert", you MUST use `ask_user` (yesno type) to ask the user if they want to revert these files automatically. Do NOT revert without explicit confirmation.

## Standard Workflow (Mandatory)

To ensure a consistent experience, the agent MUST follow these steps in order:

1.  **Mandatory Input Gathering**: Use `ask_user` to prompt the user for the following information. Do NOT proceed without these:
    - **Pending Changelist IDs**: (e.g., `default`, `12345`).
    - **Output Directory Path**: The location where the generated summary report should be saved.
2.  **Execute Check**: Run the `check_line_endings.cjs` script with the provided parameters.
3.  **Present Results**: Show the console output and provide the path to the generated Markdown report.
4.  **Confirm Revert**: If "Safe to Revert" files exist, use `ask_user` to ask: "Would you like to revert the files that only have line-ending differences now?"
5.  **Execute Revert (Optional)**: If the user confirms, execute `p4 revert` for the identified files using the correct `P4CLIENT`.

## Tools & Scripts

### Check Line Endings Script
```bash
node scripts/check_line_endings.cjs <cl_id_1> <cl_id_2> ... --output-dir <path>
```

### Output Categories
- ✅ **Safe to Revert**: Only line endings differ. A revert command is provided.
- ⚠️ **Real Modifications**: Content has actual changes.
- ℹ️ **Skipped**: Non-text files (binary, etc.) are ignored.
