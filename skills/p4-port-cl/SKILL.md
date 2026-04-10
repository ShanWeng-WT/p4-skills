---
name: p4-port-cl
description: >
  Ports the changes from a submitted Perforce changelist in one workspace/stream
  to one or more other workspaces/streams. Trigger whenever the user wants to apply,
  port, propagate, replicate, copy, or mirror a P4 changelist's edits across multiple
  workspaces or streams — even if they phrase it as "apply the same changes",
  "do the same thing in other branches", "copy CL to other workspaces", or
  "make the same fix across all versions".
---

# Port P4 Changelist Across Workspaces

This skill takes a submitted Perforce changelist from a source workspace and ports the same
file-level changes to one or more target workspaces. The file paths may differ between streams
(different game numbers, folder naming conventions, etc.), so the skill locates the matching
file in each target before applying the edit.

## When to Use

Trigger this skill when the user wants to:

- Port a changelist's changes to other P4 workspaces / streams / branches
- Port a fix across multiple product versions
- Copy the same file edits from one stream to several others
- Replicate a submitted CL to a list of target workspaces

Do **not** use this skill for:

- `p4 integrate` / `p4 merge` workflows (those are server-side branch operations)
- Exporting changelist contents to disk (use the `p4-export` skill instead)
- Moving files between changelists within the same workspace

## What You Need from the User

1. **Source changelist number** (required) — the submitted CL whose changes to port.
2. **Source workspace/client name** (required) — identifies which stream the CL belongs to.
   Often inferrable from the CL description output.
3. **Target workspace names** (required) — one or more P4 client names to port to.

If any of these are missing, ask the user before proceeding.

## Workflow

### Step 0: Workspace Validation

Before running any P4 commands, follow the `p4-workspace-check` skill to ensure the correct
client context. Since this skill operates across multiple workspaces, use the `-c <client>`
flag on every `p4` command rather than relying on the default client.

### Step 1: Analyze the Source Changelist

```
p4 -c <source_client> describe -s <CL_number>
```

From the output, extract:

- **Changelist description** — save this for reuse as the description on the new CLs.
- **Affected files** — the list of depot paths and their actions (edit, add, delete, etc.).

For each file with an `edit` action, retrieve the actual diff to understand what changed:

```
p4 -c <source_client> diff2 -u <depot_path>#<prev_rev> <depot_path>#<head_rev>
```

The revision numbers are: `#<head_rev>` is the revision shown in `describe`, and
`#<prev_rev>` is `head_rev - 1`.

Record the diff hunks — these are what you will apply to the target files.

### Step 2: Locate Matching Files in Each Target Workspace

For each affected file, extract the **filename** (e.g., `UIAuto.prefab`) and search for it
in each target workspace's stream:

```
p4 -c <target_client> files //<stream_root>/.../filename
```

Where `<stream_root>` is derived from the target client's stream path. You can determine it
from the client spec or by convention (e.g., `OSX_ShanWeng_Fish2.1_NewRnd` maps to
`//OSX/Fish2.1_NewRnd/...`).

**Important considerations:**

- The path structure may vary between streams. A file at `Game109/Perfabs/UIPrefab/X.prefab`
  in one stream might be at `Game130/Perfabs/UIPrefab/X.prefab` or
  `Game170/Prefabs/ScenePrefab/X.prefab` in another. Search by filename, not by full path.
- If the search returns **multiple** matches, present them to the user and ask which one
  to use.
- If the search returns **no** matches, report that the file was not found in this workspace
  and skip it. Do not fail the entire operation.

### Step 3: Verify the Target Files Have the Lines to Change

Before blindly applying a diff, confirm that the target file contains the lines that the diff
expects to modify. Use `p4 print` with `Select-String` (Windows) or `grep` to check:

```
p4 -c <target_client> print <depot_path> | Select-String "<pattern>"
```

If the lines to change don't exist (the file has already been modified or has different
content), warn the user and skip that file.

### Step 4: Open Files for Edit and Apply Changes

For each confirmed target file:

1. **Sync** to head revision:
   ```
   p4 -c <target_client> sync <depot_path>
   ```

2. **Open for edit**:
   ```
   p4 -c <target_client> edit <depot_path>
   ```

3. **Get the local file path**:
   ```
   p4 -c <target_client> where <depot_path>
   ```
   The third column of the output is the local filesystem path.

4. **Apply the change** to the local file. Use the appropriate method depending on the nature
   of the diff:

   - **Simple value replacement** (like `m_HideMobileInput: 1` to `m_HideMobileInput: 0`):
     Use PowerShell string replacement on all matching lines:
     ```powershell
     (Get-Content "<local_path>") -replace '<old_pattern>', '<new_value>' |
       Set-Content "<local_path>"
     ```

   - **Block insertion/deletion**: Use the Edit tool or PowerShell scripting to insert or
     remove the specific lines identified in the diff.

   - **Complex multi-hunk diffs**: For diffs with many scattered changes, consider using
     `p4 print` to get the source file's final content and applying the diff programmatically.

5. **Verify** the change was applied by searching the modified file for the expected new values.

### Step 5: Create Pending Changelists and Move Files

For each target workspace, create a new pending changelist with the same description as the
source CL:

```powershell
$desc = "<original CL description>"
$form = "Change: new`nClient: <target_client>`nUser: <username>`nStatus: new`nDescription:`n`t$desc`n"
$form | p4 -c <target_client> change -i
```

Then move each edited file into the new changelist:

```
p4 -c <target_client> reopen -c <new_CL_number> <depot_path>
```

### Step 6: Report Results

Present a summary table to the user showing:

| Workspace | File Found | File Path | Changes Applied | New CL |
|---|---|---|---|---|
| Target_1 | Yes | `<relative path>` | N occurrences | XXXXX |
| Target_2 | Not found | -- | Skipped | -- |
| ... | ... | ... | ... | ... |

Always include:
- Which workspaces were successfully ported to
- Which workspaces were skipped and why
- The new changelist numbers (so the user can review and submit them)
- The changelist description that was applied

## Edge Cases

- **File has `add` action in source**: The file is new. Search the target workspace anyway —
  if it doesn't exist, you may need to `p4 add` it after creating it locally. Ask the user
  whether to proceed.
- **File has `delete` action in source**: The file was removed. In the target workspace,
  open it for delete: `p4 -c <target_client> delete <depot_path>`.
- **File has `move/add` or `move/delete` actions**: These indicate a rename. Inform the user
  and ask how to handle it, since the path mapping may differ.
- **Binary files**: Cannot apply text diffs. Use `p4 print -o` to get the source version and
  overwrite the target file directly, after confirming with the user.
- **File is already open in target workspace**: Check with `p4 -c <target_client> opened`
  before editing. If the file is already open in another CL, warn the user and ask whether
  to proceed (the reopen will move it out of its current CL).

## Important Notes

- This skill applies changes at the **file content** level, not via P4 integration.
  The resulting changelists are independent edits, not branch integrations.
- Always use `-c <client>` on every `p4` command to ensure you're operating in the correct
  workspace context.
- When multiple files are affected by the source CL, process them all — don't stop at the
  first one.
- The changelist description should be preserved exactly as-is from the source CL (including
  any non-ASCII characters like CJK text).
