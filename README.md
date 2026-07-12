# Hospitalist Scheduler

A web-based quarterly scheduling tool for hospitalist groups. Providers mark the days they cannot work; the software generates a complete quarterly schedule that covers every shift, honors those requests, and keeps workloads even across the group — without adding administrative burden.

Most hospitalist groups default to rigid 7-on / 7-off rotations because flexible scheduling is too time-consuming to manage by hand. This tool does that work automatically: it builds 48 candidate schedules per quarter, scores them on coverage, request honoring, rounding-block structure, and fairness, and keeps the best one. Scheduling staff review and publish instead of assembling the grid manually.

It is **not** a qGenda replacement — day-to-day operations (swaps, call, paging) stay in your existing system. This tool owns quarterly schedule *creation* and imports qGenda history to keep fairness tracking accurate.

## Key features

**For scheduling staff (admin)**
- One-click quarterly generation — 48 scored candidates, best one wins
- Excel-style schedule grid: click any cell to change a shift, fill modes for bulk edits, undo, name-column resize, search filter
- One-click Excel export: the quarter grid (with daily coverage counts) plus a per-provider totals sheet as a .xlsx download
- Staffing gap detection: short/overstaffed days flagged in red; click a date to see which shift is off and the fairest candidate providers to fix it
- Fairness dashboard: flags outliers in total shifts, swing shifts, weekend load, and unmet required requests (FTE-adjusted)
- qGenda Excel import (Calendar by Task): bootstraps a new site's roster and reconciles actual worked shifts each quarter
- Named versions (save/restore snapshots), clear-schedule and reset-group maintenance flows with typed confirmation
- Temporary staffing overrides for high-census periods
- Holiday auto-assignment: Thanksgiving/Christmas alternate year to year — never both in one year, never two Christmases in a row
- Stress test and demo mode: simulate request loads to see when the schedule strains, or build a temporary throwaway schedule for presentations
- Guided tutorial: a spotlight walkthrough of the generated schedule (honored/missed requests, staffing flags, coverage rows, fairness) — auto-shown once in demo modes, available anytime via the Tutorial button

**For physicians and APPs**
- Time-off request calendar: mark dates **Required** (must honor) or **Optional** (honor when possible), with per-quarter limits on totals, required days, and weekends enforced as you click
- Personal portal: full schedule calendar, monthly totals vs. annual FTE target, pace tracking, and request-honoring rate vs. peers
- Honoring-rate priority: providers whose requests were missed get higher priority the next quarter
- Strict 7-on / 7-off styles still fully supported (mixed-shift or swing-block), side by side with variable scheduling

**Scheduling engine guarantees**
- 5–7 day rounding blocks protect provider–patient continuity — flexibility never produces scattered one-day assignments
- Max 2 consecutive swing days for variable providers; rest day enforced after a swing stretch before returning to rounding
- Daily coverage targets for rounders, admitters, nocturnists, and APP roles checked across the entire quarter
- Workload balanced by FTE within the quarter and year-to-date, using base-schedule history (voluntary extra shifts don't count against anyone)
- Part-time providers share the variable pool: same rest rules and request honoring, FTE-scaled workload (fewer blocks, not shorter ones)
- APPs default to strict 7-on/7-off; an APP set to Variable joins the request-honoring variable pool with APP coverage targets
- Rest and rotation rules hold across quarter boundaries — strict phases, swing-only rhythms, and variable rest carry over (no marathon stretches at the seam)
- Holiday rotation enforced at request time: a provider who had last Christmas off cannot request the next one off

## Architecture

Deliberately simple: **one HTML file, no build step, no framework.**

```
index.html                     The entire app — markup, CSS, and JS (~8,000 lines)
supabase-security-current.sql  Reference schema + row-level security policies
```

- **Frontend:** vanilla JS + CSS in `index.html`. Talks to Supabase via raw REST `fetch` (no client library). Deployable on any static host.
- **Backend:** [Supabase](https://supabase.com) — Auth (email/password) plus Postgres with RLS.
- **State:** each site (group) stores its full app state as a JSON blob in one `schedule_data` row, keyed by group id. Autosaves on edit; a 30-second poll picks up changes from other sessions.
- **Multi-site:** `groups` / `profiles` / `memberships` tables scope access. A master admin can create and switch between sites; group admins manage one site; physicians see their own portal.
- **Demo account:** a designated demo login runs entirely against `sessionStorage` — it seeds realistic year-to-date history on first login and never writes to the shared database.

### Data model (Supabase)

| Table | Purpose |
|---|---|
| `groups` | One row per hospitalist site |
| `profiles` | One row per auth user (`is_master_admin` flag) |
| `memberships` | User → group → role (`admin` / `physician`) → optional provider `doc_id` |
| `schedule_data` | One JSON blob of app state per group |
| `versions` | Named snapshots for restore, scoped by group |
| `activity_events` | Usage/audit log, written via a `security definer` RPC |

All tables have row-level security; see [supabase-security-current.sql](supabase-security-current.sql).

## Getting started

### 1. Supabase setup
1. Create a Supabase project.
2. Run `supabase-security-current.sql` in the SQL editor (review first — it assumes `schedule_data` and `versions` tables already exist with `id`/`data`/`updated_at` and `name`/`data`/`saved_at`/`saved_by`/`group_id` columns respectively).
3. Create auth users, then for each: a `profiles` row, and a `memberships` row linking them to a group with a role (and a `doc_id` for physicians).

### 2. Configure the app
Near the top of `index.html`, set:
```js
const SUPABASE_URL  = 'https://<your-project>.supabase.co';
const SUPABASE_ANON = '<your-anon-key>';
```
The anon key is safe to ship in the client **only because RLS enforces access** — never put a service-role key here.

### 3. Deploy
Host `index.html` on any static host (GitHub Pages, Netlify, S3, a hospital intranet server). No build step.

### 4. Onboard a site
1. Sign in as master admin → **Settings → Group Onboarding** → create the site.
2. **Settings → Data Management → Import qGenda Excel** to build the roster from a Calendar-by-Task export, or add providers manually in **Settings → Provider Roster**.
3. Set daily staffing counts and request limits in **Settings → Schedule Parameters**.
4. Have providers submit time-off requests, then **Generate Schedule** for the quarter.

## Typical quarter workflow

1. **Providers** submit required/optional dates in their portal (limits enforced automatically).
2. **Admin** clicks *Generate Schedule* — the engine builds and scores 48 candidates.
3. **Admin** reviews red-flagged staffing days and the fairness check, adjusts cells as needed, and saves.
4. After the quarter ends, **admin** re-imports the qGenda export so actual worked shifts (including voluntary extras) feed the fairness history.

## Provider types & scheduling styles

| Type | Behavior |
|---|---|
| Standard — Variable | The flexible pool (any FTE); requests honored, 5–7 day R blocks with 1–2 day swing tails |
| Standard — Strict 7-on/7-off (mixed) | Fixed rotation, 5R+2S pattern; requests disabled |
| Standard — Strict 7-on/7-off (swing block) | Alternating full 7R / 7S weeks; requests disabled |
| Nocturnist | Night coverage blocks, scheduled separately |
| Medical Director | Weekday rounding only |
| Swing Only | Alternating 7-day swing weeks |
| PRN / Track Only | Never auto-scheduled; shifts tracked when filled manually |

## Project status

Functional and in active use; currently being hardened for broader rollout. The prioritized fix list in [OPUS-FIX-INSTRUCTIONS.md](OPUS-FIX-INSTRUCTIONS.md) has been applied (see the status header in that file). Notable recent changes:

- Physician request submission now writes to its own `time_off_requests` table (RLS limits `schedule_data` writes to admins); rows are merged into app state on load
- Quarter/year dropdowns are generated dynamically from the current date (the old hardcoded lists ended at 2026 Q4)
- Saves now use optimistic concurrency (a concurrent admin's save triggers a reload instead of being silently overwritten), and saving is blocked after a failed load so defaults can never overwrite real data
- **Deployments must re-run `supabase-security-current.sql`**: it adds the `time_off_requests` table and — critically — column-level grants on `profiles` that close a privilege-escalation hole (any authenticated user could previously set their own `is_master_admin` flag via the REST API)

## Development notes

- Built primarily with AI pair-programming (Codex / Claude Code).
- No test suite yet; the built-in **Stress Test** (Settings → Stress Test / Demo Mode) is the current regression check for the scheduling engine.
- Keep the single-file architecture unless there's a strong reason not to — it is the deployment story.
