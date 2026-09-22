# Performance Considerations

## BigQuery — partitioning, clustering, cost

- The raw GA4 export (`events_*`) is already **date-sharded** (one table per
  day) rather than partitioned in the newer sense — every query in
  `sql/01_staging_ga4_flatten.sql` filters on `_TABLE_SUFFIX` first so
  BigQuery's wildcard-table pruning skips shards outside range before
  scanning any bytes.
- The downstream views in `ga4_dw` are defined as views over that filtered
  range for this project's sample scope. In production, they'd instead be
  materialized into **native partitioned tables** (`PARTITION BY event_date`)
  with **clustering on `user_pseudo_id`** (the highest-cardinality column
  queried in equality/range filters — sessionization and per-user lookups)
  — clustering co-locates that user's rows physically, cutting bytes
  scanned on the window-function-heavy sessionization query specifically.
- `SELECT *` is never used against the raw export in any script — GA4's
  export is wide (100+ nested fields per row); every unused column is
  bytes billed for nothing, since BigQuery bills by columns scanned, not
  rows returned.
- The `UNNEST(event_params)` subqueries in `01_staging_ga4_flatten.sql` are
  intentionally scoped to only the params actually used downstream, rather
  than unnesting the whole array — an unscoped `UNNEST` on the full
  `event_params` array fans out every row by however many params GA4
  attached to that event (often 10-20), multiplying scan cost for no
  benefit if most aren't queried.

## Power BI / VertiPaq

- **Column cardinality drives model size** far more than row count in
  VertiPaq's compressed columnstore. `event_id` (a synthesized MD5 hash,
  effectively unique per row) is the single most expensive column in this
  model — kept only because it's needed as a join key during load; it is
  **not** exposed in the report's field list or used in any visual, since
  a high-cardinality text column pulled into a visual forces the formula
  engine to materialize huge intermediate tables.
- Where possible, high-cardinality surrogate keys (`page_key`, `source_key`,
  `item_key`) are MD5 hashes truncated to hex strings rather than full
  GUIDs — shorter strings compress better under VertiPaq's dictionary
  encoding than long ones with high entropy.
- Relationships are on integer/short-hash keys, never on the raw
  `page_location` URL string — joining on a long text column is
  measurably slower than joining on a dictionary-encoded short key,
  because the relationship engine has to compare and hash more bytes per
  row.
- `Purchase Events (slow pattern)` vs `Purchase Events (fast pattern)` in
  `dax/time_intelligence_measures.dax` is kept in the repo deliberately —
  see `dax/context_transition_notes.md` for the full walk-through of why
  one pushes work to the storage engine and the other doesn't.

## Where to verify these claims, not just assert them

- **BigQuery**: the query validator / dry-run estimate (top-right of the
  BigQuery console, or `bq query --dry_run`) shows bytes-to-be-scanned
  before running — compare `SELECT *` vs the scoped column list on
  `01_staging_ga4_flatten.sql` to see the difference directly.
- **Power BI**: DAX Studio's **Server Timings** tab splits any measure's
  evaluation into Storage Engine time vs Formula Engine time — the two
  `Purchase Events` measures above are a ready-made A/B pair to run through
  it, since they should produce visibly different FE/SE splits.
