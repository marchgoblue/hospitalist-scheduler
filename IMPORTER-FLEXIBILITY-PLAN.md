# Plan: Flexible Schedule Importer

Status: **not built yet** — waiting on a sample export from a second scheduling
system to validate Reader B's header detection (see "What to bring" at the
bottom). This doc captures the agreed design so the work can start cold.

## Why this is easier than it sounds

The import pipeline in `index.html` has three stages, and **only stage 1 is
qGenda-specific**:

| Stage | Function(s) | Format-specific? |
|---|---|---|
| 1. Spreadsheet → records | `parseQgendaWorkbook` | **Yes** — hardcoded to qGenda "Calendar by Task" (a `Monday` header row, a dates row, then paired shift/provider columns per day) |
| 2. Shift-label mapping | `showQgendaTaskMapModal` / `applyQgendaTaskMap` | No — admin maps whatever labels the file contains to R/S/N/X/APP codes |
| 3. Provider-name matching | `qgMatchName` + `showQgendaMapModal` | No — fuzzy match with manual-correction dropdowns; "— skip —" and "+ Add as new provider" already work |

Stage 1's entire job is to produce an array of records shaped:

```js
{ date: Date, task: 'Rounder 3',        // raw shift label, cleaned via qgCleanTask()
  rawName: 'Smith, Jane' }              // raw provider name as written in the file
```

Anything that can produce that array gets stages 2 and 3 — preview, task
mapping, name matching, bonus-shift accounting — for free.

## Design: layout readers + a manual fallback

Replace the body of `parseQgendaWorkbook` with a dispatcher that tries readers
in order; the first one that confidently matches wins. All readers output the
record shape above.

### Reader A — qGenda Calendar by Task (exists today)
Keep the current parser byte-for-byte as the first reader so existing sites are
completely unaffected.

### Reader B — flat table (the big win)
One assignment per row, with a header row. This is what most systems' "export
to Excel/CSV" produces (qGenda's other report types, ShiftAdmin, Amion, etc.).

- **Detection:** scan the first ~10 rows for a row where, case-insensitively:
  one cell matches a date-ish header (`date`, `day`, `shift date`), one matches
  a shift-ish header (`task`, `shift`, `assignment`, `role`, `position`), and
  one matches a name-ish header (`staff`, `provider`, `name`, `physician`,
  `employee`). Then require that ≥80% of the next 10 rows parse as dates in the
  date column. Both conditions met → confident match.
- **Parsing:** iterate rows below the header; skip blanks; dates may be
  strings or Excel serials (`cellDates:true` already handles serials).
- **Validate the header vocabulary against a real second-system export before
  shipping** — that's the sample file this plan is waiting on.

### Reader C — roster grid
Provider names down the first column, dates across the top row, shift codes in
the cells (or the transpose). This is what nearly every homemade Excel schedule
looks like.

- **Detection:** first row ≥70% parseable as dates AND first column ≥70%
  person-like (reuse `qgLooksLikePersonName`, loosened to accept `First Last`
  as well as `Last, First`). Also try the transpose.
- **Parsing:** each non-empty cell → one record with the cell text as `task`.
  Cell values like `R` / `S` / custom codes flow into the existing task-map
  modal, which is exactly what it's for.

### Fallback — manual column picker (the "no additional build ever" guarantee)
If no reader matches, don't fail. Show a small modal with the first ~8 rows of
the file rendered as a table and three dropdowns: *Which column is the date? The
provider? The shift?* (plus "first data row" if the header guess is wrong).
Then parse as Reader B with those choices. Optionally persist the choice per
site (e.g. `S.cfg.importColumnMap`) so re-imports are one click.

### Freebies to include in the same change
- **CSV support:** accept `.csv` in `handleQgendaFile` / `importQgenda` — the
  already-loaded SheetJS parses CSV through the same `XLSX.read` call.
- **UI rename:** "qGenda Import" → "Schedule Import" in the Data Management
  section and drop-zone copy (keep a "works great with qGenda Calendar by
  Task" hint).
- **Reader tag in the preview:** show which reader matched ("Detected: flat
  table") so admins can sanity-check before importing.

## Known limits (by design)
- Excel/CSV **tables** only. PDFs, screenshots, and color-coded spreadsheets
  (where meaning lives in cell fill, not text) are out of scope.
- Multi-sheet workbooks: keep the current behavior (first sheet), but consider
  a sheet picker in the fallback modal.

## Suggested build order
1. Reader B + CSV + reader dispatcher (Reader A untouched) — covers most
   third-party systems.
2. Manual column-picker fallback — covers everything else tabular, forever.
3. Reader C (roster grid) — quality-of-life for homemade spreadsheets.
4. UI rename + detected-reader tag.

## Testing
A headless Playwright harness pattern already exists from prior work (build a
synthetic `S`, call the parser, assert on the records). For this change: craft
three tiny fixture workbooks with `XLSX.utils.aoa_to_sheet` (one per reader),
feed them through `parseQgendaWorkbook`'s replacement, and assert the record
arrays match — plus one garbage file to confirm the fallback modal path fires.

## What to bring before starting
A real export (or even a screenshot of the header row) from the other
scheduling system(s) you want supported, so Reader B's header vocabulary is
validated against reality instead of guessed.
