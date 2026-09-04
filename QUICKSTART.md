# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

Before you start, read the "What this kit is not" section of `README.md`. Short version: this is GPS-verified door proof plus a local extract of fulls in, empties out, and paid. It is **not** a tax invoice, **not** a cylinder serial log, and **not** the official Pertamina MAP / Indane / CRE / DOE book.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\lpg-ops` (Windows) or `/Users/yourname/lpg-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\lpg-ops\\lpg-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "Gas Jaya". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my lpg-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Gas Jaya in Jakarta. Rupiah, Western Indonesia Time. Save that to settings and create the Stop Record form.

The AI saves your settings (including `currency_code` / `currency_symbol` — local money stays in SQLite; ZenSched meters are always USD) and calls `form_create` once (free) to build the Stop Record your drivers fill in: cylinders delivered, empties collected, paid (Cash / Account / Unpaid), optional receipt photo (max 1). No signature. It stores the form id so every stop gets it.

If you are in Mexico, Spain, the Philippines, or India, say so here and it will set `timezone_offset`, `currency_code`, and `currency_symbol`, then you edit the seeded 3 / 12 / 15 / 45 kg prices. Indonesia, the Philippines, and India have no DST. Most of Mexico (including Mexico City) stays `-06:00` year-round after abolishing DST in 2022. Spain has DST (`+02:00` in summer, `+01:00` in winter) — tell the AI when clocks change.

## 6. Add your first two customers

> Add Warung Bu Sari, 0812-555-0144, Jl. Kemang Raya 12, Jakarta Selatan 12730. Daily 3 kg at Rp 20.000 starting Monday 2026-09-07 at 7. Pager 3319, anjing di belakang. North loop stop 1.

> Add Rumah Pak Andi, andi@example.com, 0813-555-0190, Jl. Metro Pondok Indah, Jakarta Selatan 12310. Weekly 12 kg Rp 185.000, Tuesday 2026-09-08 at 9. Deposit 2 tabung. Call from the gate.

Behind the scenes the AI inserts each customer and stop, calls `location_create` (geocode, $0.03 USD, may trigger the $5 activation deposit the first time), creates a 60-day `event_create` for the place, attaches the Stop Record with `form_assign`, and saves the IDs. The ZenSched location/event label is stop code + street (`S-1 · Jl. Kemang Raya 12`), never the customer name. Names, phones, gate notes, and deposits stay in the local database. You just see a confirmation.

## 7. Invite your driver

> Invite Budi Santoso at budi@example.com as a driver and make him my default.

Budi gets an email ($0.25 USD), installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [iOS TestFlight](https://testflight.apple.com/join/Wp51m5Yq)), and activates. Give him the pager code and the gate note yourself; the AI will not put them in ZenSched.

## 8. Schedule the week

> Schedule this week for Budi.

The AI reads `stops_due` (daily places already expand to one row per remaining day), creates one shift per stop on ZenSched, and summarizes by day. Budi gets a push notification for each, with the Stop Record attached. It will confirm each stop is about $0.25 USD once he punches and you read the record, or $0.35 if he attaches a receipt photo.

## 9. After the work is done

> Record this week's jobs, show me the cash log and the cylinder log, then draft invoices for anyone with uninvoiced work.

The AI pulls the completed, GPS-verified shifts and the Stop Records from ZenSched (reading records is metered in USD, so it tells you the cost first), saves a per-visit summary in rupiah, advances Bu Sari by one day and Andi by seven, shows the cash and cylinder extracts (your copy, not a tax invoice and not your MAP / Indane / CRE / DOE book), creates invoice records for Account / Unpaid only, and writes out each invoice as text you can paste into WhatsApp.

> Andi paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, the tax / serial-log boundary, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above
