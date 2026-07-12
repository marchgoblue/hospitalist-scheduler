# Bug-Fix Instructions — Hospitalist Scheduler

> **STATUS (July 2026): APPLIED.** All Priority 1 and Priority 2 items below, and
> Priority 3 items 3.1–3.8, were implemented on branch
> `claude/code-review-recommendations-cbtqkb`. Item 1.3 used the preferred
> `time_off_requests` table approach; item 2.8 implemented the relaxed 3+ R rule
> (run the built-in Stress Test to confirm shortage counts before relying on it).
> Additional fixes beyond this list: a `profiles` column-level-grant fix for a
> privilege-escalation hole, a save guard after failed loads, optimistic
> concurrency on saves, the qGenda parser's hardcoded "Athens" break generalized,
> and the xlsx library upgraded to 0.20.3 with an SRI hash.
> **Re-run `supabase-security-current.sql` in each Supabase project.**
> This file is kept for historical reference.

Paste this file (or its sections) into Claude Opus as the task prompt. Context: the entire
app is a single `index.html` (~8,000 lines, vanilla JS + Supabase via raw REST fetch) plus
`supabase-security-current.sql` (RLS reference). App state is one JSON blob `S` saved whole
to the `schedule_data` table, keyed by group id. **All fixes must be non-breaking — the app
is functional and being demoed to hospital leadership.** Line numbers are approximate
(theme/branding edits were already applied); search for the quoted code instead.

Already fixed — do NOT redo: theme color consolidation (#1f5a99→#1b4d8f, flat navy
physician header, :root tokens), login-screen branding, favicon/title, emoji removal,
announcement-textarea `${S.announcement||''}` literal, phys-page-hdr negative margins.

---

## Priority 1 — Demo-critical

### 1.1 Dynamic quarter/year dropdowns (time bomb: breaks Oct 2026)
The selects `#myq-sel`, `#req-q-sel` are hardcoded `2025-1`…`2026-4`; `#yr-sel` is
hardcoded 2025–2027; `#my-cal-year` 2025–2027. On init the app sets the request quarter
to "next quarter" — from Q4 2026 onward that value (`2027-1`) doesn't exist in the list,
so the select silently falls back to its first option while internal state points at a
different quarter.
**Fix:** at startup (before the init code that sets `.value` on these selects), populate
each of these selects in JS from the current date: years from (currentYear − 1) to
(currentYear + 2), quarters Q1–Q4 with the same label format as the existing options.
Remove the hardcoded `<option>` lists from the HTML. Keep element IDs and value formats
(`YYYY-Q` for quarter selects, `YYYY` for year selects) identical.

### 1.2 qGenda import ignores manual match corrections
In `runQgendaImport`, find:
```js
records.forEach(r=>{ if(!r.docId&&corrections[r.rawName]) r.docId=corrections[r.rawName]; });
```
Corrections are only applied to records with no auto-match, so (a) fixing a wrong fuzzy
match in the dropdown is silently discarded and shifts import under the wrong physician,
and (b) selecting "— skip —" on an auto-matched name still imports it.
**Fix:** build `corrections` so it records EVERY dropdown's value (including empty = skip),
then apply unconditionally: if the dropdown for `r.rawName` exists, `r.docId` becomes its
value (or `null` for skip), regardless of the auto-match. Apply the same logic in
`previewQgendaImport` (it has the same `rec.docId||corrections[rec.rawName]` pattern) so
the preview matches the import.

### 1.3 Physician request submission vs RLS (verify, then restructure)
`saveData()` upserts the entire state blob into `schedule_data`, but the RLS policy
`schedule_data_write_admin` (see `supabase-security-current.sql`) only allows group
admins to write. A physician-role login therefore gets a 403 when submitting time-off
requests (works today only for the sessionStorage demo account and admins).
**Fix (preferred):** create a `time_off_requests` table (columns: user_id, group_id,
doc_id, quarter_key, required jsonb, optional jsonb, submitted_at) with RLS "user writes
own rows / group members read". Change `submitMyRequests`, `toggleRequestDate` persistence
and `clearMyRequests` to write there when `isPhysician()`; on `loadData()`, merge those
rows into `S.requests` so all existing rendering/generation code is untouched. Admin-side
writes can keep using the blob. Do not loosen `schedule_data` RLS — that would let any
physician overwrite the whole schedule.
**Minimum viable alternative** if time is short: verify with a real physician account; if
submission 403s, surface a clear error and demo the physician portal with the demo account.

### 1.4 Self-triggering "Schedule updated by admin" toast
`pollForChanges` compares `updated_at` to `lastSyncTime`, but `saveData()` never advances
`lastSyncTime`. Within 30s of any admin save, the app reloads its own write, re-renders
(clearing row/column selection, staffing focus, fill mode) and shows a false toast.
**Fix:** in `saveData()` on success, set `lastSyncTime=Date.now()`. Better: have the
upsert return the row (`Prefer: return=representation`) and use its `updated_at`.

### 1.5 Hardcoded provider migrations leak across sites
In `applyMigrations`, remove (or gate to the original group id) this block:
```js
const u={odeyinka:{first:'Oladipo'},chapagain:{first:'Sudeep'},walls:{...},ahmadani:{...},tahir:{...}};
```
Any site with a coincidentally-matching provider id gets silently mutated on every load.

## Priority 2 — Real bugs, smaller blast radius

2.1 **"Change My Password" invisible on My Schedule page.** The button at the bottom of
`#pg-myschd` uses class `phys-nav-btn` (white-on-transparent, designed for the navy
header) on a light background, inside a wrapper with a white-alpha border. Restyle as a
normal `.btn btn-sm` and give the wrapper a normal `var(--line)` border-top.

2.2 **"Save Version" modal never closes.** In `saveVersion`'s OK callback, add
`document.getElementById('modal').style.display='none'` after the success toast
(match `confirmRestoreVersion` / `confirmClearSchedule`).

2.3 **Coverage footer mislabels overstaffing.** In `renderSchedule`'s `coverageRow`,
the branch chain is ok / bad / low — a day with MORE than target renders amber "low".
Add `else if(v>dayTarget)cls+=' cov-high'` (the `cov-high` CSS class already exists).

2.4 **Toast timer race.** `toast()` sets a hide `setTimeout` without clearing the
previous one, so back-to-back toasts vanish early. Store the timer id in a module
variable and `clearTimeout` it at the top of `toast()`.

2.5 **"Clear All" requests doesn't persist.** `clearMyRequests` clears in-memory state
and toasts "Cleared" but never saves; a reload restores the dates. Either call the
request-persistence path (see 1.3) or change the toast to "Cleared — press Submit
Requests to save."

2.6 **`addPhysician` id keeps unsafe characters.** Its id is
`(last+first).toLowerCase().replace(/\s+/g,'')+'_'+Date.now()` — an apostrophe
(O'Brien) survives and breaks every inline `onclick="...('${doc.id}')"`. Use the same
sanitizer as the qGenda path: `.replace(/[^a-z0-9]/g,'')` (keep the timestamp suffix).
Do NOT change existing ids in stored data.

2.7 **Unescaped names in generated HTML.** Provider names, version names, and titles are
interpolated into `title="..."`/`value="..."` attributes and inline text in many render
functions without escaping. Route them through the existing `qgEsc()` helper. Be
systematic but careful: only wrap the interpolated VALUE, never the surrounding markup.

2.8 **Dead "emergency S" layer.** `canBeS_emergency` is identical to `canBeS_normal`, so
scheduling STEP 4c never relaxes anything despite its comment ("early transition when S
supply is thin"). Either implement the relaxed rule (allow S transition after 3+
consecutive R instead of `MIN_R_HARD`=5, keeping all other guards) or delete the layer
and its call site. If you change generation behavior, run the built-in Stress Test
(Settings → Stress Test) before/after to confirm shortage counts don't regress.

2.9 **Rules text contradicts config.** The request portal shows hardcoded "Maximum 20 OFF
dates per quarter … 6 can span weekends". Render this sentence from `S.cfg.maxReq` /
`S.cfg.maxWeekendReq` (e.g., populate it in `renderMyRequestCal`).

2.10 **Fairness check misses conflicts.** In `recheckFairness`, `unmetRequired` counts
only `'R'||'S'` on required-off days; include `'H'`, `'N'`, `'APP_NS'`, `'APP_NX'` (match
`_scoreScheduleCandidate`'s list).

2.11 **Double startup load.** Remove the bare top-level `loadData();` call near the INIT
section (appInit/completeLogin already load after auth). Keep everything else in init.

2.12 **Escape doesn't close the modal.** Extend the existing `keydown` listener: on
Escape, also hide `#modal` (but not while a confirm-typing input like RESTORE/CLEAR has
focus — simplest: always close; the destructive actions require typed confirmation anyway).

## Priority 3 — Polish (optional, time permitting)

3.1 Debounce `saveAnnouncement` (copy the `autoSaveCfg` 500ms timer pattern) — currently
a full-blob save fires per keystroke.
3.2 Weekly View: `nav('week')` resets `S.ui.wkStart` to the current week every visit —
only set it if null.
3.3 Fill-mode hint says "cycle R→S→N→OFF" but `SHIFT_CYCLE` includes X — update the text.
3.4 Legend hardcodes shift times ("Rounding 7a–5p", "Swing 3p–1a"); make configurable or
neutral. Same for "target ~8 per quarter" text on physician pages.
3.5 Replace the three native `confirm()` dialogs (`clearMyRequests`, `importData`,
`runDemoMode`) with the existing `showModal` for visual consistency.
3.6 Print: add `@page{size:landscape}` and test the quarterly grid; consider a
month-per-page print layout.
3.7 Mobile pass for `#pg-myreq` / `#pg-myschd` (single `@media (max-width:640px)` block);
physicians will open these on phones.
3.8 Hide or relabel the Admin/Physician role switch for physician logins (currently a
physician can browse the full admin view read-only, including group honoring-rate ranks).

## Verification checklist (after each batch)
- Open the app, sign in as admin: generate a quarter, click cells, save, wait 35s — no
  spurious "Schedule updated by admin" toast.
- qGenda import: change one auto-matched name to a different provider and to "— skip —";
  Preview must reflect both.
- Sign in as a physician (or demo account): submit, clear, and re-submit requests.
- Save a version → modal closes; restore it.
- No console errors on load or navigation.
