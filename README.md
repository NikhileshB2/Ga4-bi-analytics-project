# GA4 E-Commerce Analytics Engineering & Power BI Semantic Model

A end-to-end BI engineering project: raw **GA4 BigQuery export** → dimensional
warehouse → **Power BI semantic model** → executive dashboard + **paginated
(RDL) report**. Built to demonstrate production-grade Power BI / analytics
engineering practice, not just a dashboard.

Data source: Google's public GA4 sample export
`bigquery-public-data.ga4_obfuscated_sample_ecommerce` (BigQuery, free to
query, no PII, fully nested/repeated event schema — the real thing recruiters
mean when they say "GA4 event-level data").

---

## Why this project maps to the role

| Requirement | Where it's demonstrated |
|---|---|
| 4+ yrs Power BI, production reporting | Star-schema semantic model + governed dataset layer (`docs/design_decisions.md`) |
| Advanced DAX — time intelligence, calc groups, context transition | `dax/time_intelligence_measures.dax`, `dax/calculation_groups.dax` |
| Semantic model design over a dimensional warehouse | `sql/03`–`07`, `architecture/star-schema-diagram.md` |
| Incremental refresh, composite models, aggregations, gateways/capacity | `power-query/incremental_refresh_source.pq`, `docs/design_decisions.md` §4–6 |
| SQL + cloud warehouse (BigQuery) — partitioning, clustering, cost | `sql/*.sql` headers, `docs/performance_considerations.md` |
| GA4 event-level modelling: nested/repeated data, sessionisation, conversions | `sql/01_staging_ga4_flatten.sql`, `sql/02_sessionization.sql` — the differentiator |
| Paginated reports (RDL) / pixel-accurate PDF export | `paginated-report/rdl_spec.md` |
| Report/dashboard design judgement, can defend layout | `docs/design_decisions.md` §7 |
| Power Query / M, source control & deployment discipline | `power-query/*.pq`, this repo's structure + `docs/design_decisions.md` §8 |

---

## Architecture

```
GA4 BigQuery export (nested, event-per-row, daily sharded tables)
        │
        ▼
sql/01_staging_ga4_flatten.sql      -- UNNEST event_params, items, user_properties
        │
        ▼
sql/02_sessionization.sql           -- 30-min inactivity rule, session_id, entrance/exit
        │
        ▼
Dimensional model (BigQuery views, queried live or imported)
   dim_date, dim_user, dim_page, dim_traffic_source, dim_item
   fact_events, fact_sessions, fact_conversions
        │
        ▼
Power BI semantic model (star schema, single-direction relationships)
   Power Query (power-query/incremental_refresh_source.pq) — incremental refresh
   DAX measures (dax/*.dax) — time intelligence, calc groups
        │
        ├──► Interactive report (executive dashboard)
        └──► Paginated report (RDL) — pixel-perfect PDF export (paginated-report/)
```

See `architecture/star-schema-diagram.md` for the full entity-relationship
diagram (Mermaid — renders natively on GitHub).

## Repo layout

```
ga4-bi-analytics-project/
├── README.md
├── architecture/
│   └── star-schema-diagram.md
├── sql/
│   ├── 01_staging_ga4_flatten.sql
│   ├── 02_sessionization.sql
│   ├── 03_dim_date.sql
│   ├── 04_dim_user.sql
│   ├── 05_dim_traffic_source_and_item.sql
│   ├── 06_fact_events_and_sessions.sql
│   └── 07_fact_conversions.sql
├── power-query/
│   └── incremental_refresh_source.pq
├── dax/
│   ├── time_intelligence_measures.dax
│   ├── calculation_groups.dax
│   └── context_transition_notes.md
├── paginated-report/
│   └── rdl_spec.md
└── docs/
    ├── design_decisions.md
    └── performance_considerations.md
```

## How to reproduce it (one day's work, in order)

1. **BigQuery (1–2 hrs)** — Create a free-tier GCP project, open BigQuery,
   run `sql/01` through `sql/07` in order against
   `bigquery-public-data.ga4_obfuscated_sample_ecommerce`. Each script is a
   `CREATE OR REPLACE VIEW`, so the warehouse layer is idempotent and
   re-runnable — save the views into your own dataset, e.g. `ga4_dw`.
2. **Power BI Desktop (2–3 hrs)** — New DirectQuery/Import model →
   BigQuery connector → point at the `ga4_dw` views. Paste the M query in
   `power-query/incremental_refresh_source.pq` into `fact_events` and
   `fact_sessions` and set up the incremental refresh policy in Power Query
   parameters (`RangeStart` / `RangeEnd`). Build relationships per
   `architecture/star-schema-diagram.md` (single-direction, dims → facts).
3. **DAX (1–2 hrs)** — Add the measures from `dax/time_intelligence_measures.dax`,
   then the calculation group from `dax/calculation_groups.dax` (needs
   Tabular Editor 2/3, free). Read `dax/context_transition_notes.md` — it's
   written as interview-ready explanations, not just code.
4. **Report canvas (1–2 hrs)** — Build the executive dashboard per the
   layout rationale in `docs/design_decisions.md` §7.
5. **Paginated report (1 hr)** — Build the RDL in Power BI Report Builder
   following `paginated-report/rdl_spec.md`; export to PDF to prove
   pixel-accurate output.
6. **Publish** — `git init`, commit everything except the `.pbix` binary
   itself if you want a lightweight repo (or use Git LFS for it — see
   `docs/design_decisions.md` §8), push to GitHub, add a screenshot or GIF
   of the finished dashboard to the README.

## What's intentionally *not* included

A `.pbix` binary isn't included in this scaffold — Power BI files are binary
and don't diff well in git, so the honest professional move (documented in
`docs/design_decisions.md` §8) is to keep the model logic in version-controlled
text (SQL, M, DAX) and treat the `.pbix` as a build artifact, optionally
tracked with Git LFS or Power BI's `.pbip` (Project) format, which serializes
the report as text (TMDL) instead. If you have Power BI Desktop with the
Power BI Project preview feature enabled, save as `.pbip` for a fully
diffable, GitHub-native model — this is the current best-practice deployment
pattern and is worth mentioning explicitly in an interview.
