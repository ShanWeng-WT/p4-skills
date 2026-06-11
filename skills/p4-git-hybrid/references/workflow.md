# Hybrid P4-Git Workflow Strategies

## The "Bridge" Branch Strategy
Maintain one Git branch (e.g., `p4-main`) that is always in sync with the current Perforce state.
- Create feature branches off `p4-main`.
- When ready to submit, merge feature branch back to `p4-main`.
- Run `p4 reconcile` or `p4 edit` on the files modified in `p4-main`.

## Handling Re-mapping
If your P4 workspace uses complex client mappings, ensure your `.gitignore` and `.p4ignore` are relative to the workspace root.

## File Permissions
Perforce often sets files to read-only unless checked out.
- **Tip**: Set `allwrite` in your P4 client specification to keep files writable, which makes Git operations smoother.
- **Command**: `p4 client` -> check the `Options:` field.

## Dealing with Deletions
If you delete a file in Git (`git rm`), you must also tell P4: `p4 delete <file>`. `p4 reconcile` is very helpful here as it can detect missing files and mark them for delete in P4.
