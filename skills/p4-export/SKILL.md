---
name: p4-export
description: Exports all files from a Perforce changelist to a local directory, preserving the relative directory structure. Use when the user wants to extract or export the contents of a specific P4 changelist to a local directory.
---

# P4 Changelist Export Skill

Export all files from a Perforce changelist into a local directory, preserving the depot's relative folder structure.

## When to Activate

Use this skill when the user wants to:

- Export or extract files from a specific Perforce changelist number
- Get a local copy of all files in a submitted changelist
- Save changelist contents to disk for review, archival, or sharing

Do **not** use when the goal is to apply or port changes to another workspace/stream — that workflow uses `p4 describe`, `p4 print`, `p4 edit`, and direct file editing instead.

## Prerequisites

- The Perforce command-line client (`p4`) must be installed and available in PATH.
- The user must have network access to the Perforce server and permissions to read the files in the target changelist.
- Workspace validation is **not required** — the script uses only server-side commands (`p4 describe`, `p4 print`) that do not depend on the local workspace mapping.

## Parameters

The user must provide:

1. **Changelist number** (required) — the Perforce changelist to export.

The user may optionally provide:

2. **Output directory** — the base directory where the export folder will be created. Defaults to the current working directory.

## Execution

Run the export script with PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_directory>\p4export.ps1" <changelist_number>
```

To specify a custom output directory:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_directory>\p4export.ps1" <changelist_number> -OutputDir "<output_path>"
```

Replace `<skill_directory>` with the absolute path to the directory containing `p4export.ps1`.

## What the Script Does

1. Runs `p4 describe -s <changelist>` to list all affected files and their actions.
2. Auto-detects the depot root from the file paths (first two path components, e.g. `//depot/stream/`).
3. Creates an output folder named `CL<changelist>` under the output directory.
4. For each file in the changelist:
   - **Skips** files with delete actions (`delete`, `move/delete`, `purge`) since there is no content to export.
   - Strips the depot root to compute a relative path.
   - Recreates the directory structure locally.
   - Uses `p4 print -o` to write the file at the correct revision to the local path.
5. Prints a summary showing the count of succeeded, skipped, and failed files.

## Output

The exported files are placed in:

```
<output_directory>/CL<changelist_number>/
    <relative_path_1>
    <relative_path_2>
    ...
```

The relative paths mirror the depot structure below the auto-detected depot root.

## Error Handling

- If `p4` is not in PATH, the script exits with an error.
- If the changelist does not exist, the script exits with an error.
- If a changelist has no affected files, the script exits cleanly with a warning.
- Individual file failures (e.g., permission issues, directory creation errors) are logged but do not stop the export of remaining files. A summary of failed files is printed at the end.
- The script exits with code 1 if any files failed, and code 0 otherwise.
