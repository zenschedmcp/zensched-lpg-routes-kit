# ZenSched LPG Cylinder-Route Reference Kit

A copy-pasteable setup for a 1–4 truck LPG / propane cylinder delivery route (households, warungs, restaurants, small commercial) in Indonesia, Mexico, Spain, the Philippines, or India that wants an AI assistant to run daily dispatch, GPS-verified door stops, cylinder in/out counts, and local-currency invoicing. ZenSched handles the live schedule, the driver's phone app, GPS check-ins at the door, and the Stop Record (fulls, empties, paid, optional receipt photo). A small local database on your computer holds your customers, places, prices, cadence, visit summaries, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule today", "add a daily warung", "how many 3 kg did Budi drop", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What this kit is not — read this first

**What it is:** GPS-verified proof that a driver was at the door, a Stop Record (cylinders delivered, empties collected, Cash / Account / Unpaid, optional receipt photo), a local extract of those records for your own files, and account invoices built from completed stops.

**What it is not:**

- **Not a tax invoice.** `cash_log` and the draft invoice text are *your* copy of what the driver typed (date, stop, fulls, empties, paid). They are not an Indonesian e-Faktur, not a Mexican CFDI, not a Spanish factura, not a Philippine OR, and not an Indian GST invoice. Your tax office still wants *their* document.
- **Not the official Pertamina MAP / Indane / CRE / DOE book.** The Stop Record is proof-of-exchange for you and the customer. It is not Pertamina MAP / MyPertamina subsidy recording, not an Indane / Bharatgas / HP Gas OMC portal, not CRE volumetric or CFDI, not a DOE LTO or RA 11592 cylinder-swapping registry, and not a MITECO price filing. Keep those in the oil-company app or the permit binder. Do not tell an ESDM / CRE / DOE inspector "it's in ZenSched."
- **Not cylinder track-and-trace.** The kit counts bottles. It does not store serial numbers, RFID, or subsidized-3 kg identity (MyPertamina and equivalents). GPS proves the driver was at the address, not that a numbered bottle changed hands.
- **Not a signed legal receipt.** The Stop Record has no signature field. On ZenSched a signature field replaces the Submit button, so adding one would make every stop look like the customer had signed something. Submitting the form is just submitting the form.
- **Not a route optimiser.** The AI sequences by the `stop_order` you give it. It does not solve a travelling-salesman loop.

If any of those is a deal-breaker, this kit is not for you. If you want daily/weekly cadence, door-GPS, and a local extract you can file next to your real tax forms and official MAP / OMC / CRE / DOE book, read on.

## What lives where

**ZenSched (source of truth for what happened, when, and where):**

- Locations (delivery places with GPS coordinates; the check-in radius is a **policy** setting)
- Workers (drivers with the mobile app)
- Events (one "LPG" job per stop, renewed every 60 days)
- Shifts (each scheduled visit, with push notifications to the driver)
- GPS punches (check-in/check-out with distance-from-the-pin verification)
- The Stop Record form (fulls, empties, paid, optional receipt photo) and every submission
- Timesheets (verified hours worked)
- **Meters, always USD** (geocode $0.03, invite $0.25, GPS $0.10, form read $0.05 / $0.15)

**Local SQLite database (`lpg-ops.db`, on your computer):**

- Customer contact, deposit notes, billing terms
- Stops (places), including access notes (gate, dog, "call first") that **never leave your computer**
- Your price list in **local currency** (3 / 12 / 15 / 45 kg seeded; edit for MX / ES / PH / IN sizes)
- Drivers
- Completed visits with a summary of each Stop Record, the cash and cylinder extracts, and invoices
- Your settings (timezone, **currency_code / currency_symbol**, default driver, invoice prefix, Stop Record form id)

**Never duplicated:** the live schedule, punches, timesheets, and receipt photos stay in ZenSched. The local database only stores *references* to them plus a short per-visit summary so you can answer "how many 3 kg at Bu Sari" without paying to re-read reports.

**Two currencies, never mixed.** Rupiah, pesos, euros, pesos/php, or rupees live only in SQLite. ZenSched's bill is always US dollars. The AI states meter costs in USD and cylinder prices in your symbol.

### Privacy note

Customer names, phones, gate codes, dogs, "call first" instructions, and outstanding cylinder deposits stay in the local database (`customers.customer_name` / phones, `stops.access_notes`, `customers.deposit_notes`). `SKILL.md` forbids the AI from putting them into any ZenSched field. The location name and event title are **stop code + street** (`S-1 · Jl. Kemang Raya 12`), never the customer name. Give gate/deposit notes to your driver yourself, by whatever channel you trust. ZenSched only ever sees the stop code, the street address, and the GPS pin.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `form_submissions`, `shift_list`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `lpg-ops.db` on your computer.

When you say "schedule today" or "schedule this week," the AI reads who is due from the local database. **Daily** stops expand to one shift per remaining day in the next 7; **weekly** stops emit a single day. It creates those shifts on ZenSched and tells you what it did. Your driver sees the stops in the app, checks in at the door (GPS-verified), swaps cylinders, fills in the Stop Record, and checks out. Later you say "record today's route" and the AI pulls the completed shifts and records, saves a summary locally, advances each stop (daily +1 day, weekly +7 days, on-demand clears it), and leads with anyone marked Unpaid. "Cash log for yesterday" is a local query. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

A typical stop costs about **$0.25 USD** on ZenSched without a photo (GPS in $0.10 + out $0.10 + basic Stop Record read $0.05) or **$0.35** if the driver attaches the optional receipt photo. Geocoding a new place is $0.03 once. The AI states the USD cost before it spends.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\lpg-ops`
- Mac: `/Users/yourname/lpg-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\lpg-ops.db` (Windows) or `/lpg-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "lpg-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/lpg-ops/lpg-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\lpg-ops\\lpg-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My LPG Route" (use my real business name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my lpg-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run the statements one at a time and confirm the tables exist. The `lpg-ops.db` file now exists in your folder, pre-loaded with a starter cylinder price list you can change.

If you happen to have the `sqlite3` command-line tool, `sqlite3 lpg-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Gas Jaya in Jakarta. Rupiah, Western Indonesia Time. Save that in settings, and set up the Stop Record form.

It writes those to the `settings` table (including local currency), creates the Stop Record form on ZenSched (free), and saves the form id so every stop gets it automatically.

**Check-in radius.** The default pin uses `checkin_radius_m=75` on `location_create`, but ZenSched **enforces** the radius through the account's policy, not per place. With geofencing on it raises anything under 100 m to about 91 m (300 ft), so 75 behaves as roughly a house-and-alley circle. For a warung set back from the road, or a pin that lands on the avenue, ask the AI to "set the check-in radius to 150 m" (`policy_update`) or to move the pin onto the door (`location_update`, free). Do not ask it to widen the radius "on that location" — that field is informational only.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Some things are metered **in USD**: creating a location (geocoding, $0.03), inviting a driver ($0.25), each GPS-verified check-in or check-out ($0.10), and reading a Stop Record ($0.05, or $0.15 when it has a receipt photo). When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

A typical stop is about $0.25 USD (in + out + basic record) or $0.35 with a photo. A driver doing 25 stops a day is about $6.25–$8.75 in meters that day, plus $0.03 the first time you add each place. The AI states the USD cost before it spends. Your cylinder prices stay in local currency.

## Using it

Everything after setup is plain English. Examples:

- "Add Warung Bu Sari, 0812-555-0144, Jl. Kemang Raya 12, Jakarta Selatan. Daily 3 kg Rp 20.000 starting Monday. Pager 3319, anjing di belakang."
- "Add a weekly 12 kg for Rumah Pak Andi at Pondok Indah, Tuesday 9, Rp 185.000. Deposit 2 tabung."
- "Invite Budi Santoso, budi@example.com, and make him the default driver."
- "Schedule today for Budi."
- "Schedule this week."
- "Record today's route."
- "Cash log for yesterday."
- "Who didn't pay?"
- "Draft invoices for account customers."
- "Andi paid INV-2026-0001."
- "Pause the warung until next week."
- "We're in Mexico City now — pesos, Central time, 20 kg and 30 kg."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount in **local currency**, which visits) and the AI writes out a plain-text invoice you can paste into WhatsApp or an email, with a line per stop and a note that the visit was GPS-verified. It does **not** generate a PDF, an e-Faktur / CFDI / factura, email it for you, or collect payment. Cash stops are omitted (already collected). When the customer pays, tell the AI ("Andi paid INV-2026-0001") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for drivers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)

When you invite a driver, they get an email, install the app, and can immediately see their stops, check in and out with GPS verification, and fill in the Stop Record. The record is attached to each stop automatically. There is no signature step — they tap Submit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `lpg-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit (USD) |
| AI creates shifts at the wrong hour | Timezone not set, or a DST book still on last season's offset | "Set my timezone offset to +07:00 in settings." ID / PH / IN have no DST. Most of Mexico (incl. CDMX) abolished DST in 2022 and stays `-06:00`; Baja California and some border municipios still change. Spain has DST: `+02:00` late March–late October, `+01:00` the rest — refresh the setting when clocks change or autumn shifts land an hour off. |
| Invoices show the wrong symbol | Currency not set | "Set currency to MXN / $" (or EUR / €, PHP / ₱, INR / ₹) |
| Shift creation fails for dates a couple of months out | The stop's 60-day ZenSched event has expired | Say "renew the events"; the AI runs the roll-over in `SKILL.md` and retries |
| Driver's check-in not GPS-verified at a house | Geocoded pin is at the avenue, driver is in the alley, or a large compound | Ask the AI to widen `checkin_radius_m` with `policy_update` (not on the location), or run `location_update` / `location_refine` ($0.10) |
| Driver does not see the Stop Record | Form not assigned to that place's event | "Attach the Stop Record to that stop's event" (`form_assign` with `event_id`). That installs the form on **existing** shifts — do not cancel and recreate the shift. |
| "Cash log" comes back empty | Visits not recorded yet, or the driver marked Account / Unpaid | "Record today's route" first; only `paid = Cash` rows appear |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |
| AI refuses to put a pager code in ZenSched | Working as intended | Give it to the driver directly |
| AI offers an e-Faktur, CFDI, bottle serial report, or MAP / Indane / CRE / DOE filing | It shouldn't | This kit does not produce those; use your tax / subsidy / official-portal system |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations (schedule, punches, forms); SQLite is authoritative for CRM, cadence, visit summaries, cash/cylinder extracts, and billing in **local currency**; each side stores only the other's **integer** IDs, plus a per-visit report summary cached locally because submission reads are metered. ZenSched meters stay in USD on the ZenSched side.

**Data model decisions.**

- **Customers → stops (places) → visits.** Cadence and the pin live on the stop so one account can have a daily warung and a weekly house.
- One ZenSched **location** per stop, permanent, stored on `stops.zensched_location_id` as an integer. Created with `location_create(name, street_address=..., checkin_radius_m=75, idempotency_key=...)`. **`name` is `stops.stop_label` = stop code + street** (`S-1 · Jl. Kemang Raya 12`), never the customer name. `checkin_radius_m` on `location_create` is informational; the enforced radius is `policy_update(0, '{"checkin_radius_m": N}')`, and with geofencing on the platform raises values under 100 m to 300 ft.
- **Events are capped at 60 days by ZenSched**, so an event cannot be a permanent job template. Each stop holds its *current* event in `stops.zensched_event_id` and its last covered date in `stops.event_valid_until`. The agent creates a new event (`event_create(location_id, title="LPG - <stop_label>", start_date, end_date=start+59 days, idempotency_key="event-stop-{stop_id}-{YYYYMMDD}")`) whenever a shift date is later than `event_valid_until`, calls `form_assign(form_id, event_id=...)` on it (that also installs the form on existing shifts — do not cancel/recreate), and updates the row. `stops_due` exposes `event_needs_roll` per row and `events_expiring` lists stops due for renewal within 14 days. Shifts already created on the old event remain valid. When recording a completed visit whose `event_id` no longer matches a stop, the agent falls back to `event_get(event_id).location_id` against `stops.zensched_location_id`. A daily stop is ~60 punches per window.
- **Cadence is daily / weekly / on-demand.** `stops.service_frequency` is `daily | weekly | on-demand`. `stops_due` uses `date('now','localtime')` and a `date_offsets` spine (0..6): daily stops emit one row per remaining day in today..today+6 on or after `next_service_date`; weekly / on-demand emit a single row on `next_service_date` if it is within 7 days. Each row carries `visit_date`, `start_iso` / `end_iso`, and the shift `idempotency_key`.
- **The `advance_service_date_on_visit` trigger** sets `last_service_date` and `next_service_date` on every visit insert: **+1 day** / +7 days / NULL. Recording a one-off on a recurring stop also moves the cadence; `SKILL.md` tells the agent to set the date back if the owner says so.
- **`update_float_on_visit`** adds `delivered − empties` to `stops.float_cylinders`. `float_watch` lists stops whose float is not zero.
- **`fill_visit_amount`** sets `amount = cylinders_delivered * stops.unit_price` when the agent leaves `amount` NULL (local currency). An explicit 0 is kept.
- Rate lives on the **stop** (`unit_price`) so a shop can charge off-list. `stops.cylinder_type_id` is the default size.
- `visits.zensched_shift_id` and `drivers.zensched_worker_id` are integer `UNIQUE`. `visits.report_dc_id` holds the form `submission_id`. `paid_status` is `CHECK`-constrained to the form's option labels (`Cash` / `Account` / `Unpaid`).
- `fill_visit_driver` sets `driver_id` from `zensched_worker_id` when the agent leaves it NULL. `fill_visit_duration_*` fills minutes from punches.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`. Cash visits are omitted from `visits_to_invoice`.
- **`cash_log` / `cylinder_log` / `unpaid_flags`** are views over recorded visits. They do not transmit anything and are not a tax form.
- `stops.access_notes`, `customers.deposit_notes`, `customers.customer_name`, and phones are the columns that must never be sent to ZenSched; `SKILL.md` rule 6 enforces it. `stop_label` is stop code + street after insert (`UPDATE … SET stop_label = 'S-' || stop_id || ' · ' || address`). `stops_due` still *selects* `access_notes` and `customer_name` so the agent can talk to the owner; those must never go into a ZenSched field.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.

**Stop Record form.** Created once with `form_create(title, fields_json, idempotency_key="form-stop-record")`; the exact `fields_json` is in `SKILL.md` and `example-workflow.md` (byte-identical) and was validated against ZenSched's `_validate_fields`. Every field carries an explicit `identifier` so submission `data` keys are stable (`cylinders_delivered`, `empties_collected`, `paid`, `receipt`; section `sec_stop`). Option keys are derived by ZenSched from the labels (lowercase, non-alphanumerics → `_`, truncated at 30 characters); `Cash` / `Account` / `Unpaid` become `cash` / `account` / `unpaid`. **No `signature` field** — the phone keeps a Submit button, and submitting is not a legal attestation. Attaching is `form_assign(form_id, event_id=...)`.

**Idempotency keys.** Deterministic, derived from local IDs:

- location: `loc-stop-{stop_id}`
- event: `event-stop-{stop_id}-{YYYYMMDD window start}`
- shift: `shift-stop-{stop_id}-{YYYYMMDD}` for the first visit that day; a same-day extra or a driver swap after `shift_cancel` appends `-2`, then `-3`, … — never reuse a cancelled key (24-hour replay would return the cancelled shift)
- worker: `worker-{email}`
- form: `form-stop-record`; assignment: `assign-stop-record-{event_id}`
- cancel: `cancel-shift-{shift_id}`

ZenSched caches idempotent responses for 24 hours. `form_assign(event_id)` installs the Stop Record on existing shifts; do not cancel and recreate to attach it.

**Timestamps.** `shift_create` takes `start` and `end` in ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-07T07:00:00+07:00`), never `Z`. The view builds these strings so the agent does not have to. ID / PH / IN have no DST. Most of Mexico stays `-06:00` after the 2022 abolition (Baja California and some border municipios still change). Spain switches `+02:00` / `+01:00` — refresh `timezone_offset` when clocks change.

**Metered reads.** `form_submissions` and `form_export` bill $0.05 per submission read ($0.15 with media); `form_export` is preferred for a day or a week at a time. The kit stores the summary and media URLs on `visits` on first read so later cash-log questions are answered from SQLite. `shift_list`, `shift_status`, `event_get`, and `timesheet_export(mode="hours"|"raw")` are free.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by splitting the file into its **63** statements with `sqlite3.complete_statement` and executing each individually (as the MCP server does) **twice** for idempotency (seed rows not duplicated), then exercising: all 8 tables, 9 views, and 10 triggers present; every view on an empty database; `date_offsets` 0..6; settings defaults (IDR / Rp / `+07:00` / 07:00); integer types on every ZenSched ID column; frequency CHECK rejecting `monthly`; `preferred_start` rejecting `7am`; `stops_due` expanding a daily stop to 7 days (today .. today+6), a mid-window daily to the remaining 4, a weekly to one row, and excluding +20-day and inactive-customer rows; `start_iso` / `end_iso` / `idempotency_key` / worker / minutes (3 kg → +10 min, 12 kg → +12 min); `event_needs_roll` flipping exactly when `event_valid_until < visit_date` (and when NULL); `events_expiring`; `route_board`; `float_watch` omitting zero float; `advance_service_date_on_visit` for daily (+1, 2026-09-04 → 2026-09-05), weekly (+7), and on-demand (NULL); `fill_visit_amount` (`2 × 20000` → 40000) and explicit amount kept; `fill_visit_driver` from `zensched_worker_id`; `fill_visit_duration` (~11 min); `update_float_on_visit` (2−2=0, then 2+1−0=3); UNIQUE on `zensched_shift_id`; `paid_status` CHECK; negative delivered rejected; `cash_log` / `unpaid_flags` / `visits_to_invoice` (Cash omitted, Account + Unpaid included); invoice numbering (auto `INV-YYYY-0001`, explicit number kept); `invoices_outstanding` overdue / aging; cascade delete and driver set-null; `updated_at`. Form payload validated against `_validate_fields` (5 fields, no signature, SKILL.md byte-identical to example-workflow.md, option keys `cash` / `account` / `unpaid` ≤ 30 characters). **153/153** checks, all passing.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.
