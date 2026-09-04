# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative. ZenSched IDs are integers.

Shop: **Gas Jaya**, Jakarta, Indonesia, Western Indonesia Time (`+07:00`). Local currency **IDR / Rp**. Two customers (daily 3 kg warung + weekly 12 kg house), one driver, then cash extract and one account invoice.

ZenSched meters in the billing blobs are **USD**. They are never written into `lpg-ops.db`.

Access notes (gate, dog) and deposit notes stay in SQLite. They are never sent to ZenSched.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = My LPG Route, timezone_offset = +07:00,
    currency_code = IDR, currency_symbol = Rp,
    default_worker_id = NULL, default_shift_start = 07:00,
    default_shift_minutes = 12, invoice_due_days = 7, invoice_prefix = INV,
    stop_record_form_id = NULL, event_window_days = 60,
    default_checkin_radius_m = 75
```

## "My business is Gas Jaya in Jakarta. Rupiah, Western Indonesia Time."

```
sqlite_execute: UPDATE settings SET value = 'Gas Jaya' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '+07:00' WHERE key = 'timezone_offset';
sqlite_execute: UPDATE settings SET value = 'IDR' WHERE key = 'currency_code';
sqlite_execute: UPDATE settings SET value = 'Rp' WHERE key = 'currency_symbol';
```

> Saved. I'll schedule everything in WIB (+07:00) and show prices in rupiah. You don't have a Stop Record form yet; it's free to create and every stop will come back with fulls delivered, empties collected, paid (Cash / Account / Unpaid), and an optional receipt photo. No signature — this is an internal stop record, not a tax invoice. Want me to set it up now?

Owner: *"yes"*

```
form_create:
  title: "Stop Record"
  idempotency_key: "form-stop-record"
  fields_json: (the JSON below, passed as one string)
```

```json
[
  {"type": "section", "label": "Stop record", "identifier": "sec_stop",
   "text": "Count fulls delivered and empties collected before you leave. Receipt photo is optional. This is an internal stop record, not a tax invoice."},
  {"type": "number", "label": "Cylinders delivered", "identifier": "cylinders_delivered", "required": true},
  {"type": "number", "label": "Empties collected", "identifier": "empties_collected", "required": true},
  {"type": "select", "label": "Paid", "identifier": "paid", "required": true,
   "options": ["Cash", "Account", "Unpaid"]},
  {"type": "photo", "label": "Receipt photo", "identifier": "receipt", "max_images": 1}
]
```

```
  → form_id: 501, fields: [ ...5 fields echoed with identifiers... ]

sqlite_execute: UPDATE settings SET value = '501' WHERE key = 'stop_record_form_id';
```

> Stop Record form created. I'll attach it to every place automatically. There is no signature step.

## "Add Warung Bu Sari, 0812-555-0144, Jl. Kemang Raya 12, Jakarta Selatan 12730. Daily 3 kg at Rp 20.000 starting Monday 2026-09-07 at 7. Pager 3319, anjing di belakang. North loop stop 1."

```
sqlite_query:   SELECT type_id, unit_price, default_minutes FROM cylinder_types WHERE code = '3kg';
  → 1, 20000, 10

sqlite_execute:
  INSERT INTO customers (customer_name, contact_phone, billing_notes)
  VALUES ('Warung Bu Sari', '0812-555-0144', 'pays cash at the door');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO stops (customer_id, stop_label, address, city, state, zip, country,
                     access_notes, route_label, stop_order, cylinder_type_id,
                     unit_price, service_frequency, next_service_date, preferred_start)
  VALUES (1, 'Warung Bu Sari', 'Jl. Kemang Raya 12', 'Jakarta Selatan', 'DKI Jakarta',
          '12730', 'ID',
          'Pager 3319. Anjing di belakang — panggil dulu.',
          'North loop', 1, 1,
          20000, 'daily', '2026-09-07', '07:00');
  → lastInsertRowid = 1
```

Agent (first metered call this session, rule 11):

> Creating Bu Sari's address on ZenSched costs $0.03 for geocoding (USD meter). If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  name: "Warung Bu Sari"
  street_address: "Jl. Kemang Raya 12, Jakarta Selatan, DKI Jakarta 12730, ID"
  checkin_radius_m: 75
  idempotency_key: "loc-stop-1"
  → location_id: 9201, lat: -6.2608, lng: 106.8133, pin_quality: "street"
    billing: { meter: "geocode", units: 1, price: 0.03 }
```

The pager code is **not** in `notes`. It lives only in `stops.access_notes`. `checkin_radius_m` on the location is informational; the enforced radius is the policy (see later if Budi misses a punch).

```
event_create:
  location_id: 9201
  title: "LPG - Warung Bu Sari"
  start_date: "2026-09-07"
  end_date:   "2026-11-05"          ← start + 59 days (60-day cap)
  idempotency_key: "event-stop-1-20260907"
  → event_id: 7201

form_assign:
  form_id: 501
  event_id: 7201
  idempotency_key: "assign-stop-record-7201"
  → status: "assigned", form_id: 501, event_id: 7201, policy_id: 0

sqlite_execute:
  UPDATE stops SET zensched_location_id = 9201, zensched_event_id = 7201, event_valid_until = '2026-11-05'
  WHERE stop_id = 1;
```

> Added Warung Bu Sari, Jl. Kemang Raya 12. Daily 3 kg at Rp 20.000, next stop Monday Sep 7 at 07:00. The pager code is saved on your computer only; give it to Budi directly. Her ZenSched event runs through Nov 5; I'll renew it automatically when scheduling gets that far.

## "Add Rumah Pak Andi, andi@example.com, 0813-555-0190, Jl. Metro Pondok Indah, Jakarta Selatan 12310. Weekly 12 kg Rp 185.000, Tuesday 2026-09-08 at 9. Deposit 2 tabung. Call from the gate."

Same pattern. The agent does not re-ask about the $0.03 (owner already approved geocoding this session). Frequency is `weekly`. Deposit note is local only.

```
sqlite_query:   SELECT type_id, default_minutes FROM cylinder_types WHERE code = '12kg';
  → 2, 12

sqlite_execute:
  INSERT INTO customers (customer_name, contact_email, contact_phone,
                         billing_notes, deposit_notes)
  VALUES ('Rumah Pak Andi', 'andi@example.com', '0813-555-0190',
          'invoice weekly', 'Deposit 2 × 12 kg outstanding');
  → lastInsertRowid = 2

sqlite_execute:
  INSERT INTO stops (customer_id, stop_label, address, city, state, zip, country,
                     access_notes, route_label, stop_order, cylinder_type_id,
                     unit_price, service_frequency, next_service_date, preferred_start)
  VALUES (2, 'Rumah Pak Andi', 'Jl. Metro Pondok Indah', 'Jakarta Selatan',
          'DKI Jakarta', '12310', 'ID',
          'Call from the gate. No street parking 7–9.',
          'North loop', 2, 2,
          185000, 'weekly', '2026-09-08', '09:00');
  → lastInsertRowid = 2

location_create:
  name: "Rumah Pak Andi"
  street_address: "Jl. Metro Pondok Indah, Jakarta Selatan, DKI Jakarta 12310, ID"
  checkin_radius_m: 75
  idempotency_key: "loc-stop-2"
  → location_id: 9202

event_create:
  location_id: 9202
  title: "LPG - Rumah Pak Andi"
  start_date: "2026-09-08"
  end_date:   "2026-11-06"
  idempotency_key: "event-stop-2-20260908"
  → event_id: 7202

form_assign: form_id 501, event_id 7202, idempotency_key "assign-stop-record-7202"

sqlite_execute:
  UPDATE stops SET zensched_location_id = 9202, zensched_event_id = 7202, event_valid_until = '2026-11-06'
  WHERE stop_id = 2;
```

> Added Rumah Pak Andi, Jl. Metro Pondok Indah. Weekly 12 kg at Rp 185.000, Tuesday Sep 8 at 09:00. The deposit note stays on your computer only. This is not a tax invoice and not a bottle serial log.

## "Invite Budi Santoso, budi@example.com, and make him the default."

> Inviting a driver costs $0.25 (USD). OK?

Owner: *"yes"*

```
worker_invite:
  email: "budi@example.com"
  first_name: "Budi"
  last_name: "Santoso"
  idempotency_key: "worker-budi@example.com"
  → worker_id: 701, status: "invited", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.25 }

sqlite_execute:
  INSERT INTO drivers (driver_name, email, zensched_worker_id)
  VALUES ('Budi Santoso', 'budi@example.com', 701);
  → lastInsertRowid = 1

sqlite_execute: UPDATE settings SET value = '701' WHERE key = 'default_worker_id';
```

> Invited Budi. He'll get an email with the app link and an activation code. He's the default driver now. Remember to give him Bu Sari's pager code and Andi's gate note; I keep those off ZenSched on purpose.

Optional, if the owner wants a wider circle for Kemang alleys:

```
policy_get: policy_id 0
policy_update:
  policy_id: 0
  settings_json: '{"geofence_enabled": true, "require_on_site": true, "checkin_radius_m": 150}'
```

The radius is on the **policy**, not on either location.

## "Schedule this week for Budi."

```
sqlite_query: SELECT * FROM stops_due;
  → 2026-09-07 | Warung Bu Sari | daily | Rp 20000 | 3kg | 10 min
               | stop 1 | evt 7201 | event_needs_roll 0 | worker 701 Budi
               | start_iso 2026-09-07T07:00:00+07:00 | end_iso 2026-09-07T07:10:00+07:00
               | shift-stop-1-20260907
    2026-09-08 | Warung Bu Sari | daily | ... | shift-stop-1-20260908 | 07:00
    2026-09-08 | Rumah Pak Andi | weekly | Rp 185000 | 12kg | 12 min
               | stop 2 | evt 7202 | event_needs_roll 0 | worker 701 Budi
               | start_iso 2026-09-08T09:00:00+07:00 | end_iso 2026-09-08T09:12:00+07:00
               | shift-stop-2-20260908
    2026-09-09 … 2026-09-13 | Warung Bu Sari | daily | one row per remaining day
  (8 rows: 7 daily + 1 weekly)

shift_create:
  event_id: 7201
  worker_id: 701
  start: "2026-09-07T07:00:00+07:00"
  end:   "2026-09-07T07:10:00+07:00"
  idempotency_key: "shift-stop-1-20260907"
  → shift_id: 89011, status: "scheduled", forms_installed: [501]

(six more daily shift_create calls for Bu Sari Tue–Sun, keys shift-stop-1-20260908 … 20260913)

shift_create:
  event_id: 7202
  worker_id: 701
  start: "2026-09-08T09:00:00+07:00"
  end:   "2026-09-08T09:12:00+07:00"
  idempotency_key: "shift-stop-2-20260908"
  → shift_id: 89021, status: "scheduled", forms_installed: [501]
```

> Scheduled 8 stops for Budi this week:
> - Mon–Sun 7:00–7:10  Warung Bu Sari — daily 3 kg
> - Tue 9:00–9:12      Rumah Pak Andi — weekly 12 kg
>
> Budi has been notified in the app and every stop has the Stop Record attached. Each stop is about $0.25 once he punches and you read the record, or $0.35 if he snaps a receipt photo (USD meters). Pass him the pager code and the gate note yourself.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same shifts instead of creating duplicates.

## Budi does the work

Monday 06:58, Jl. Kemang Raya 12, in the ZenSched app: **Check in** (GPS: 22 m from the pin, verified, $0.10). Swaps two 3 kg. Opens **Stop Record**: Cylinders delivered = 2; Empties collected = 2; Paid = Cash; no photo. Submits (no signature). **Check out** 07:09 ($0.10).

Tuesday 08:57, Pondok Indah: check in at the gate. One 12 kg in, one empty out. Stop Record: delivered = 1; empties = 1; Paid = Account; one receipt photo. Check out 09:11.

## "Record this week's jobs."

```
shift_list:
  date_from: "2026-09-07"
  date_to:   "2026-09-13"
  status:    "checked_out"
  → shifts: [
      { shift_id: 89011, event_id: 7201, worker_id: 701, date: "2026-09-07", start: "07:00", end: "07:10", status: "checked_out" },
      { shift_id: 89021, event_id: 7202, worker_id: 701, date: "2026-09-08", start: "09:00", end: "09:12", status: "checked_out" }
    ], count: 2

sqlite_query: SELECT zensched_shift_id FROM visits WHERE zensched_shift_id IN (89011, 89021);
  → (none; not yet recorded)

sqlite_query: SELECT stop_id, customer_id, unit_price
              FROM stops WHERE zensched_event_id = 7201;
  → 1, 1, 20000
```

Agent (metered read, rule 11):

> There are 2 Stop Records to pull, one with a receipt photo, so about $0.20 ($0.05 + $0.15). I'll read them once and keep the summaries locally. That's the last piece of the USD meter (punches already billed when Budi checked in and out). OK?

Owner: *"go"*

```
form_export:
  form_id: 501
  since: "2026-09-07"
  until: "2026-09-13"
  format: "json"
  → row_count: 2, rows: [
      { submission_id: 5501, worker_id: 701, event_id: 7201, submitted_at: "2026-09-07 07:07:12",
        data: { cylinders_delivered: 2, empties_collected: 2, paid: "cash" },
        media: [] },
      { submission_id: 5502, worker_id: 701, event_id: 7202, submitted_at: "2026-09-08 09:09:40",
        data: { cylinders_delivered: 1, empties_collected: 1, paid: "account" },
        media: [ { cdn_url: "https://cdn.zensched.com/m/.../r1.jpg" } ] }
    ]
    billing: { meter: "form_basic+form_media", units: 2, price: 0.20 }

shift_status: shift_id 89011
  → status "checked_out", actual_in "2026-09-07T06:58:10+07:00", actual_out "2026-09-07T07:09:05+07:00",
    punches: [ { type: "in", gps_verified: true, distance_from_site_m: 22 },
               { type: "out", gps_verified: true, distance_from_site_m: 18 } ]
(free)

sqlite_execute:
  INSERT INTO visits (customer_id, stop_id, completed_date,
                      cylinders_delivered, empties_collected, paid_status,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, gps_verified, report_dc_id, photo_urls)
  VALUES (1, 1, '2026-09-07',
          2, 2, 'Cash',
          89011, 7201, 701,
          '2026-09-07T06:58:10+07:00', '2026-09-07T07:09:05+07:00', 1, 5501, '[]');
  -- trigger: amount → 40000 (2 × 20000)
  -- trigger: stops.next_service_date for Bu Sari → 2026-09-08 (+1 day)
  -- trigger: float_cylinders stays 0 (2 in, 2 out)
  -- trigger: visits.driver_id → 1 (Budi)
  -- trigger: duration_minutes → 11

sqlite_execute:
  INSERT INTO visits (customer_id, stop_id, completed_date,
                      cylinders_delivered, empties_collected, paid_status,
                      zensched_shift_id, zensched_event_id, zensched_worker_id,
                      actual_in, actual_out, gps_verified, report_dc_id, photo_urls)
  VALUES (2, 2, '2026-09-08',
          1, 1, 'Account',
          89021, 7202, 701,
          '2026-09-08T08:57:02+07:00', '2026-09-08T09:11:18+07:00', 1, 5502,
          '["https://cdn.zensched.com/m/.../r1.jpg"]');
  -- trigger: amount → 185000
  -- trigger: stops.next_service_date for Andi → 2026-09-15 (+7 days)
```

> Recorded 2 stops, both GPS-verified. Nobody unpaid.
>
> Cash today: Warung Bu Sari, 2×3 kg in / 2 empties out, **Rp 40.000**. Next due Tue Sep 8 (daily).
>
> Account: Rumah Pak Andi, 1×12 kg, **Rp 185.000**, receipt photo on file. Next due Tue Sep 15.

## "Cash log and cylinder log for last week."

```
sqlite_query: SELECT * FROM cash_log WHERE completed_date BETWEEN '2026-09-07' AND '2026-09-13';
  → 2026-09-07 | Warung Bu Sari | 2 delivered / 2 empties | Rp 40000 | Budi Santoso

sqlite_query: SELECT * FROM cylinder_log WHERE completed_date BETWEEN '2026-09-07' AND '2026-09-13';
  → 2026-09-07 | Warung Bu Sari | 3kg | 2 / 2 | net 0 | Cash | Rp 40000
    2026-09-08 | Rumah Pak Andi | 12kg | 1 / 1 | net 0 | Account | Rp 185000
```

> Your copy from the Stop Record — not a tax invoice and not a bottle serial log:
>
> Cash: Sep 7, Bu Sari, 2 full / 2 empty, Rp 40.000, Budi.
>
> Cylinders: same two rows; float at both stops is still 0.

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM visits_to_invoice;
  → Rumah Pak Andi | 1 visit | 185000 | 2026-09-08 .. 2026-09-08
  (Bu Sari Cash is omitted)

sqlite_execute:
  INSERT INTO invoices (customer_id, invoice_date, due_date, total_amount, line_items)
  SELECT v.customer_id, date('now', 'localtime'),
         date('now', 'localtime', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(v.amount),
         json_group_array(json_object('visit_id', v.visit_id, 'date', v.completed_date,
                                      'stop', s.stop_label, 'delivered', v.cylinders_delivered,
                                      'empties', v.empties_collected, 'paid', v.paid_status,
                                      'amount', v.amount, 'shift_id', v.zensched_shift_id))
  FROM visits v JOIN stops s ON s.stop_id = v.stop_id
  WHERE v.invoiced = 0 AND v.paid_status IN ('Account', 'Unpaid') AND v.customer_id = 2
  GROUP BY v.customer_id;

sqlite_execute: UPDATE visits SET invoiced = 1 WHERE invoiced = 0 AND paid_status IN ('Account', 'Unpaid') AND customer_id = 2;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE invoice_id = last_insert_rowid();
  → INV-2026-0001 | 2026-09-08 | 2026-09-15 | 185000
```

The agent then writes the invoice out as text:

> Here is the one account invoice. Bu Sari paid cash at the door, so she is not on it. Paste this into WhatsApp.
>
> ```
> Gas Jaya
> Invoice INV-2026-0001
> To: Rumah Pak Andi (andi@example.com)
> Date: Sep 8, 2026    Due: Sep 15, 2026
>
>   Sep 8    Rumah Pak Andi, 1 full / 1 empty, 12 kg    Rp 185.000
>
> Total due: Rp 185.000
> Visit GPS-verified at the door.
> ```
>
> This is not an e-Faktur. Say "sent" when it's out.

## "Sent. Andi already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now', 'localtime') WHERE invoice_number = 'INV-2026-0001';
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now', 'localtime') WHERE invoice_number = 'INV-2026-0001';
```

> Marked INV-2026-0001 sent and paid. Nothing outstanding.

## Eight weeks later: "Schedule today."

```
sqlite_query: SELECT * FROM stops_due WHERE visit_date = date('now', 'localtime');
  → 2026-11-07 | Warung Bu Sari | daily | evt 7201 | event_valid_until 2026-11-05 | event_needs_roll 1 | ...

event_create:
  location_id: 9201
  title: "LPG - Warung Bu Sari"
  start_date: "2026-11-07"
  end_date:   "2027-01-05"
  idempotency_key: "event-stop-1-20261107"
  → event_id: 7301

form_assign: form_id 501, event_id 7301, idempotency_key "assign-stop-record-7301"
sqlite_execute: UPDATE stops SET zensched_event_id = 7301, event_valid_until = '2027-01-05' WHERE stop_id = 1;

shift_create: event_id 7301, worker_id 701, start "2026-11-07T07:00:00+07:00",
              end "2026-11-07T07:10:00+07:00", idempotency_key "shift-stop-1-20261107"
```

> Scheduled Bu Sari for Sat Nov 7 07:00. Her ZenSched event was about to expire (Nov 5), so I renewed it through Jan 5. Andi is weekly and not due today.

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Bu Sari contact, daily 3 kg Rp 20.000, Andi weekly 12 kg Rp 185.000, IDR prices | SQLite | CRM in local currency; ZenSched does not model rates or recurrence |
| Pager code, dog, deposit 2 tabung | SQLite **only** | Privacy; never sent to ZenSched |
| Each stop's GPS location | ZenSched (integer ID in `stops`) | Needed for geofenced check-in |
| Each stop's current ≤60-day event and its end date | ZenSched (integer ID + `event_valid_until` in `stops`) | Shifts hang off events; renewed by the agent |
| The Stop Record form | ZenSched (ID in `settings`) | Installed on the driver's phone per shift |
| Budi, his invite, his app | ZenSched (integer ID in `drivers`) | Workforce and notifications |
| The week's shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual times | ZenSched only | Verified record; queried via `shift_status` / `timesheet_export` |
| Two Stop Records (one with a receipt photo) | ZenSched (originals); summary + photo URL in `visits` | Read once (metered USD), then cash / cylinder log from SQLite |
| Two `visits` rows referencing shift and submission IDs | SQLite | Billing + extracts in rupiah |
| One invoice, paid | SQLite | Account billing in rupiah |
| ZenSched $0.03 / $0.25 / $0.10 / $0.05 / $0.15 meters | ZenSched billing only | Always USD; never stored locally |
