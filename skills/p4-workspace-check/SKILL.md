---
name: p4-workspace-check
description: Validates that the active Perforce (P4) client workspace matches the current working directory before executing workspace-dependent P4 commands, and auto-corrects mismatches by setting P4CLIENT to the correct workspace.
---

# P4 Workspace Validation Skill

## When to Activate

Apply this skill when the user's request involves **workspace-dependent** P4 operations — commands that read or modify files in a local workspace. Workspace validation is **not required** for server-side query commands that don't depend on the local workspace.

### Workspace-Dependent Commands (validation REQUIRED)

These commands operate on local workspace files and will produce incorrect results or cause damage if run against the wrong workspace:

- `p4 sync`, `p4 submit`, `p4 resolve`, `p4 integrate`, `p4 merge`
- `p4 shelve`, `p4 unshelve`
- `p4 edit`, `p4 add`, `p4 delete`, `p4 revert`
- `p4 reconcile`, `p4 status`, `p4 opened`
- `p4 diff` (local file diffs)
- `p4 have`, `p4 where`, `p4 fstat` (when used with local/workspace paths)
- `p4 change` (creating or editing a changelist)
- Any workflow that modifies the workspace: shelving, resolving conflicts, submitting, syncing, branching, integrating

### Workspace-Independent Commands (validation NOT required)

These commands query server-side data and work correctly regardless of which client is active. Run them directly without workspace validation:

- `p4 describe <changelist>` — view changelist details
- `p4 changes` — list changelists (especially with depot paths)
- `p4 filelog` — file history
- `p4 print` — print file content from depot
- `p4 annotate` — blame / annotation info
- `p4 diff2` — server-side diff between two depot paths
- `p4 interchanges` — integration history between branches
- `p4 users`, `p4 branches`, `p4 labels`, `p4 depots`, `p4 streams`
- `p4 protects`, `p4 triggers`, `p4 counters`
- Any command that only reads from the Perforce server without referencing local files

### Edge Cases

Some commands can be either workspace-dependent or independent depending on usage:

- `p4 fstat` with **depot paths** → workspace-independent; with **local paths** → workspace-dependent
- `p4 changes` with **depot paths** → workspace-independent; with **local file arguments** → workspace-dependent
- When in doubt, perform validation.

## Validation Procedure

Before running any **workspace-dependent** P4 command for the user, you MUST perform the following validation steps in order.

### Step 1: Gather Current State

Run the following command:

```
p4 info
```

From the output, extract:
- **Client name** — the value on the `Client name:` line
- **Client root** — the value on the `Client root:` line
- **User name** — the value on the `User name:` line (needed for Step 3)

Also determine the **current working directory (CWD)** from the environment.

### Step 2: Compare Client Root to CWD

Check whether the CWD is the same as, or is a subdirectory of, the Client root reported by `p4 info`.

**Rules for comparison:**
- On Windows, perform **case-insensitive** path comparison.
- Normalize path separators (treat `/` and `\` as equivalent).
- The CWD may be the Client root itself, or any subdirectory beneath it. Both are valid matches.
- For example, if Client root is `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus` and CWD is `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus\Modules\Core`, that is a **match**.
- If Client root is `D:\FishWorkspaces\OSX_ShanWeng_Fish4_0` and CWD is `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus`, that is a **mismatch**.

**If the paths match:** Proceed to run the user's P4 commands normally. No correction is needed. Briefly confirm to the user that the workspace is correct.

**If the paths do NOT match:** Proceed to Step 3.

### Step 3: Find the Correct Client for the CWD

Use the following strategies in order to identify the correct P4 client workspace for the CWD:

#### Strategy A: Derive Client Name from Directory Name

By convention, the P4 client name is often identical to the workspace root directory name. Extract the leaf directory name from the CWD path (or the nearest ancestor that matches a workspace root).

For example:
- CWD: `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus` → candidate client name: `OSX_ShanWeng_Fish5_Plus`
- CWD: `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus\Modules` → candidate client name: `OSX_ShanWeng_Fish5_Plus`

To verify this candidate, run:

```
p4 -c <candidate_client_name> info
```

Check that the `Client root` in the output matches the CWD or an ancestor of the CWD. If it does, this is the correct client.

#### Strategy B: Search User's Clients

If Strategy A does not yield a match, list all clients for the current user:

```
p4 clients -u <username>
```

Parse the output to find a client whose `Root` directory is an ancestor of (or equal to) the CWD. Each line of output has the format:

```
Client <name> <date> root <root_path> '<description>'
```

Compare each `<root_path>` against the CWD (case-insensitive on Windows, normalized separators). Select the client whose root is the longest prefix match of the CWD (most specific match).

#### Strategy C: No Match Found

If neither strategy finds a matching client, **warn the user clearly**:
- State that no P4 client workspace was found whose root matches the current working directory.
- Show the CWD and the currently active client/root.
- Suggest the user create a workspace mapping or switch to the correct directory.
- **Do NOT proceed with P4 commands** that could affect the wrong workspace.

### Step 4: Apply the Correction

Once the correct client name is identified:

1. **Inform the user** about the mismatch. Use a message like:

   > **P4 Workspace Mismatch Detected**
   > - Active client: `OSX_ShanWeng_Fish4_0` (root: `D:\FishWorkspaces\OSX_ShanWeng_Fish4_0`)
   > - Current directory: `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus`
   > - Corrected client: `OSX_ShanWeng_Fish5_Plus` (root: `D:\FishWorkspaces\OSX_ShanWeng_Fish5_Plus`)
   >
   > All P4 commands will be run with `P4CLIENT=OSX_ShanWeng_Fish5_Plus`.

2. **Prefix every subsequent P4 command** in this interaction with the environment variable override. On Windows use:

   ```
   set P4CLIENT=<correct_client_name> && p4 <command>
   ```

   Or, equivalently, use the `-c` flag:

   ```
   p4 -c <correct_client_name> <command>
   ```

   The `-c` flag form is preferred as it is more reliable across shells.

3. **Apply this correction to ALL P4 commands** for the remainder of the interaction — not just the first one. Every single `p4` invocation must use the corrected client.

## Summary Checklist

For every P4-related user request:

- [ ] Determined whether the command is workspace-dependent or workspace-independent
- [ ] If workspace-independent: ran the command directly without validation
- [ ] If workspace-dependent: ran `p4 info` to get current client name, client root, and username
- [ ] If workspace-dependent: compared client root against CWD (case-insensitive, normalized separators)
- [ ] If mismatch: identified correct client via directory name convention or `p4 clients -u`
- [ ] If mismatch: informed the user about the mismatch and the correction
- [ ] If mismatch: prefixed all P4 commands with `-c <correct_client>` flag
- [ ] If no matching client found: warned the user and halted P4 operations
- [ ] Proceeded with the user's actual P4 request using the validated/corrected client
