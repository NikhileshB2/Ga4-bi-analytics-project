# Design Decisions

Written so every choice below can be defended in an interview, not just
described.

## 1. Import vs DirectQuery vs Composite

**Chosen: Composite model.** `dim_date`, `dim_traffic_source`, `dim_page`,
`dim_item` are small and slow-changing → **Import**, so slicers and
relationship filtering are fast (VertiPaq, in-memory). `fact_events`
(potentially large, event-grain) is set up with **incremental refresh**
(Import mode, but only the recent window re-pulled) rather than pure
DirectQuery, because DirectQuery against BigQuery pushes every visual
interaction to a live warehouse query — fine for a handful of concurrent
users, expensive and slow under real executive-dashboard usage patterns.
`fact_conversions` and `fact_sessions` are Import for the same reason.

## 2. Why aggregate tables weren't added here, but would be next

At this data volume (one month of a sample e-commerce property), an
aggregation table over `fact_events` (e.g. daily event counts by
`event_name` × `page_key`) isn't necessary — VertiPaq handles it natively.
Documented as the next step for production scale: a pre-aggregated summary
table at daily grain, with **Manage Aggregations** pointing report-level
queries at it automatically, keeping the detail fact for drill-through
only. This is the standard lever once event volume moves from "sample" to
"real GA4 production traffic" (often billions of rows/year).

## 3. Gateway consideration

BigQuery is cloud-to-cloud, so no on-premises gateway is required for
scheduled refresh — the Power BI Service can call BigQuery directly. Noted
here because it's a common trip-up: if this model instead sourced from an
on-prem SQL Server or a file share, an On-premises Data Gateway (Standard
mode, clustered for HA) would be required, and gateway throughput becomes
a real constraint on incremental refresh window sizing.

## 4. Capacity implications

Paginated reports (`paginated-report/`) and data-driven subscriptions
require **Power BI Premium / Fabric capacity** (paginated reports aren't
available on Pro-only workspaces for subscription automation). Documented
here as a licensing dependency, not an afterthought, since it directly
affects what a client/employer needs to provision before this design is
usable in production.

## 5. Incremental refresh policy

3 years archived / 1 month incremental (see
`power-query/incremental_refresh_source.pq`), "only refresh complete days"
on, change detection off. Rationale: GA4's BigQuery export is append-only
and a day's data doesn't retroactively change once landed, so there's no
need to pay the extra query cost of change detection — an explicit,
documented trade-off rather than leaving the default blindly on.

## 6. Star schema over a normalized/snowflake design

Dimensions like `dim_traffic_source` are deliberately **not** further
normalized into separate source/medium/campaign tables. A single-level
star keeps every DAX relationship a one-hop filter path, which is both
faster (VertiPaq is optimized for star schemas specifically) and easier
for a non-technical report author to reason about in the field list.

## 7. Dashboard layout rationale (the "defend your layout decisions" ask)

- **KPI strip at the top, left-to-right in the order a reader's eye
  naturally moves**: Sessions → Conversion Rate → Revenue → AOV — i.e.
  funnel order (traffic → efficiency → outcome → value), not alphabetical
  or "however they were built."
- **Trend chart directly under the KPI strip, same width**: so the visual
  answer to "is the KPI number above good?" (its trend) is immediately
  adjacent, not requiring a scroll or tab switch.
- **Channel/source breakdown as a horizontal bar, not a pie**: with more
  than 5 channels, a pie chart's angle comparisons become unreliable for
  the reader — bars support accurate ranking at a glance, which is the
  actual executive question ("which channel do we double down on").
- **Product-level detail deliberately kept off the executive page**, live
  only on a drill-through page — the exec view answers "how is the
  business doing," the drill-through answers "why," and mixing grains on
  one page is the single most common cause of a cluttered, low-trust
  executive dashboard.
- **A single slicer (date range) governs the whole page**, synced across
  all visuals — multiple independent slicers per visual is a common
  anti-pattern that erodes trust when two numbers on the same page turn
  out to be answering different questions.

## 8. Source control & deployment discipline

- Every model-defining artifact (SQL, M, DAX, calc groups) lives as
  **plain text in this repo**, not only inside a binary `.pbix`. This is
  what actually makes the project "in GitHub" in a meaningful sense — a
  `.pbix` alone in a repo is just a binary blob with no reviewable diff.
- Recommended production pattern: save the Power BI report as **`.pbip`**
  (Power BI Project format — Desktop setting: *Options > Preview features
  > Power BI Project (.pbip) save option*), which serializes the report
  and semantic model as folders of JSON/TMDL text. That makes the whole
  model — relationships, measures, formatting — diffable in pull requests,
  not just the SQL/DAX text files kept here.
- Environment promotion: dev → test → prod workspaces via **Power BI
  deployment pipelines**, with the BigQuery dataset parameterized (dev
  points at a sampled/limited dataset, prod at the full export) using the
  same M parameters pattern as `RangeStart`/`RangeEnd`.
