---
name: p4-list-changelists
description: >
  Lists submitted Perforce (P4) changelists using filters for date period, owner,
  description text, and changelist number range. Use this skill whenever the user
  wants to list, search, find, filter, report, or populate P4 changelists/CLs by
  submitter, date, description, or CL range, including natural language dates like
  today, yesterday, last week, or past week.
---

# P4 Changelist Listing

This skill lists submitted Perforce changelists that match one or more explicit filters.
The bundled PowerShell script is deterministic and expects strict filter tokens. Use the
LLM layer to infer natural-language intent, normalize dates, and produce the script tokens.

## When to Use

Trigger this skill when the user wants to:

- List or search submitted P4 changelists
- Populate a changelist report
- Find CLs by date period, owner/submitter, description text, or changelist number range
- Convert natural language requests like "yesterday's CLs by alice containing fix" into a P4 query

Do not use this skill for exporting files from a changelist, porting a changelist to another
stream, or moving files between pending changelists.

## Required Filter Format

Run the bundled script with one or more repeated `-Filter` tokens:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\scripts\Get-P4Changelists.ps1" `
  -Filter "date:2026/04/28 09:00 - 2026/04/29 18:00" `
  -Filter "owner:alice" `
  -Filter "description:fix" `
  -Filter "cl:00001-00005"
```

Supported filter keys:

| Filter | Meaning |
|---|---|
| `date:yyyy/MM/dd HH:mm - yyyy/MM/dd HH:mm` | Inclusive submitted-date range |
| `owner:<p4_user>` | Submitter / P4 user |
| `description:<literal substring>` | Case-insensitive literal substring in the changelist description |
| `cl:<min>-<max>` | Inclusive changelist number range; leading zeroes are allowed |

Rules:

- At least one filter is required.
- Each filter key can appear only once.
- The script lists submitted changelists only.
- Minute-only end times include the full ending minute. For example, `18:00` means through `18:00:59`.
- Description matching is literal and case-insensitive.

## Natural Language Date Conversion

Before running the script, convert natural-language dates into explicit `yyyy/MM/dd HH:mm`
filter tokens. Use the current session date/time unless the user provides a different anchor.

Default calendar interpretations:

| User wording | Convert to |
|---|---|
| `today` | Current calendar day `00:00` through the current time |
| `yesterday` | Previous calendar day `00:00 - 23:59` |
| `last week` | Previous Monday `00:00` through previous Sunday `23:59` |
| `past week` | Rolling last 7 days through the current time; use this only when the user says "past week" |

If the user gives exact times, preserve them. If they give dates without times, use `00:00`
for the start and `23:59` for the end.

## Execution

Run from any directory; `p4 changes` is a server-side query and does not require workspace
validation.

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\scripts\Get-P4Changelists.ps1" -Filter "<key:value>" [-Filter "<key:value>" ...]
```

For command-shape verification without connecting to the P4 server, add `-PreviewCommand`.
Do not use preview mode when the user asked for actual results.

## Output

The script prints console text in this compact form:

```text
CL | DateTime | Owner@Client | Description
12345 | 2026/04/29 18:00:12 +08:00 | alice@alice_ws | Fix login retry handling
```

`DateTime` is rendered using the P4 server UTC offset reported by `p4 info`. If the server
offset cannot be read, the script falls back to UTC and marks the timestamp with `UTC`.

When reporting results back to the user, include:

- How many submitted changelists matched
- The matching CL numbers
- Any P4 errors or invalid filter messages

## Examples

User: "List yesterday's P4 CLs by alice containing fix."

If today is `2026/04/30`, run:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\scripts\Get-P4Changelists.ps1" `
  -Filter "date:2026/04/29 00:00 - 2026/04/29 23:59" `
  -Filter "owner:alice" `
  -Filter "description:fix"
```

User: "Find CLs from 00001 to 00005."

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\scripts\Get-P4Changelists.ps1" -Filter "cl:00001-00005"
```

User: "Show submitted CLs from last week to today by shan.weng containing crash."

If the current time is `2026/04/30 15:30`, last week is `2026/04/20 00:00 - 2026/04/26 23:59`;
because the user said "to today", extend the end to the current date/time:

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\scripts\Get-P4Changelists.ps1" `
  -Filter "date:2026/04/20 00:00 - 2026/04/30 15:30" `
  -Filter "owner:shan.weng" `
  -Filter "description:crash"
```
