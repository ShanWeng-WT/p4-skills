---
name: p4-duplicate-stream
description: >
  Duplicates a Perforce (P4) stream and all its downstream child streams
  under new names. Supports renaming via substring replacement or fully
  custom naming. Use this skill whenever the user wants to duplicate, clone,
  or copy a P4 stream hierarchy, create a parallel set of streams from an
  existing stream tree, or mentions "duplicate stream", "clone stream hierarchy",
  "copy stream tree", "duplicate p4 stream", or wants to replicate a stream
  and its children with new names. Also trigger when the user asks to
  "create streams like" an existing set but with different names.
---

# Duplicate P4 Stream Hierarchy

This skill duplicates a Perforce stream and its entire downstream child hierarchy
under new names. Naming can use substring replacement (find/replace in original names)
or fully custom names provided by the user for each stream.
Only the stream specs are duplicated — no file content is copied (which is correct for
virtual streams and sufficient for other stream types where the user just needs the spec).

## When to Use

- User wants to duplicate/clone/copy a P4 stream and its children
- User wants to create a parallel stream hierarchy with renamed paths
- User mentions "duplicate stream", "clone stream tree", "copy stream hierarchy"

Do **not** use for:
- Branching file content (`p4 integrate` / `p4 merge`)
- Exporting changelist contents (use `p4-export`)
- Creating a single stream from scratch

## What You Need from the User

Gather these inputs before proceeding. Ask for any that are missing:

1. **Source stream path** — the root stream to duplicate (e.g. `//OSX/Fish2.1_NewRnd_Server`)
2. **Naming approach** — one of:
   - **Substring replacement**: an old substring and a new substring to apply to all stream
     names (e.g. replace `Fish2.1_NewRnd` with `Fish2_Plus`)
   - **Custom names**: a mapping of each original stream name to its new name. If the
     hierarchy is large, ask the user for a naming pattern or let them provide names after
     you list the discovered streams.
3. **Parent for the new root stream** — the parent stream path for the newly created root
   (e.g. `//OSX/Fish2_Plus`). This may differ from the original stream's parent.

## Workflow

### Step 0: Workspace Validation

Before running any P4 commands, follow the `p4-workspace-check` skill to ensure the correct
client context.

### Step 1: Discover the Stream Hierarchy

1. Get the source stream spec:
   ```
   p4 stream -o <source_stream>
   ```
   Save the full spec output — you'll use it as a template.

2. Find all child streams recursively. Run:
   ```
   p4 streams -F "Parent=<source_stream>"
   ```
   For each child found, also query its children, building the full tree. Alternatively,
   use a broad query and filter:
   ```
   p4 streams //<depot>/...
   ```
   and filter results whose `Parent` chain traces back to the source stream.

3. For each child stream, capture its full spec:
   ```
   p4 stream -o <child_stream>
   ```

4. Build a list of all streams to duplicate (source + all descendants), ordered so that
   parents come before children (topological order).

### Step 2: Create the New Streams

Process streams in topological order (parent before child) so each stream's parent exists
when it's created.

For each stream in the list:

1. Take the original spec text from `p4 stream -o`
2. Apply these replacements:
   - **Stream field**: replace `<old_substring>` with `<new_substring>`
   - **Name field**: replace `<old_substring>` with `<new_substring>`
   - **Parent field**:
     - For the root stream: set to the user-specified new parent
     - For child streams: replace `<old_substring>` with `<new_substring>`
   - All other fields (Owner, Type, Description, Options, Paths, Remapped, Ignored):
     copy as-is from the original
3. Pipe the modified spec to `p4 stream -i` to create the stream

**PowerShell pattern for creating a stream:**

```powershell
@"
Stream:	//Depot/NewStreamName
Name:	NewStreamName
Parent:	//Depot/ParentStream
Type:	virtual
Description:
	Created by duplicating //Depot/OriginalStream
Owner:	username
Options:	allsubmit unlocked notoparent nofromparent mergedown
Paths:
	share ...
"@ | p4 stream -i
```

Key details:
- Use PowerShell here-strings (`@"..."@`) to preserve the spec format
- Field separators are tabs (e.g. `Stream:\t//OSX/...`)
- The closing `"@` must be at the start of a new line with no leading whitespace
- Children whose parents already exist can be created in parallel

### Step 3: Verify

List the newly created streams to confirm:

```
p4 streams //<depot>/...<new_substring>...
```

Report the full list of created streams to the user.

## Tips and Edge Cases

- This works for any stream type (virtual, development, release, mainline, task).
- If a stream with the new name already exists, `p4 stream -i` will fail. Report this
  to the user rather than silently overwriting.
- The `Paths`, `Remapped`, and `Ignored` sections may contain stream-name references.
  In most cases these are relative paths (`share ...`) and don't need renaming, but if
  they contain the old substring, apply the replacement there too.
- For large hierarchies, create independent subtrees in parallel once their shared parent
  exists.
