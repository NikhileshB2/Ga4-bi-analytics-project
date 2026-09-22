# Star Schema — GA4 E-Commerce Semantic Model

```mermaid
erDiagram
    DIM_DATE ||--o{ FACT_EVENTS : "event_date"
    DIM_DATE ||--o{ FACT_SESSIONS : "session_date"
    DIM_DATE ||--o{ FACT_CONVERSIONS : "conversion_date"
    DIM_USER ||--o{ FACT_EVENTS : "user_pseudo_id"
    DIM_USER ||--o{ FACT_SESSIONS : "user_pseudo_id"
    DIM_TRAFFIC_SOURCE ||--o{ FACT_SESSIONS : "source_key"
    DIM_PAGE ||--o{ FACT_EVENTS : "page_key"
    DIM_ITEM ||--o{ FACT_CONVERSIONS : "item_key"

    DIM_DATE {
        date date_key PK
        int year
        int quarter
        int month
        string month_name
        int iso_week
        string day_name
        bool is_weekend
        date fiscal_period
    }
    DIM_USER {
        string user_pseudo_id PK
        date first_seen_date
        string acquisition_channel
        string device_category
        string geo_country
    }
    DIM_TRAFFIC_SOURCE {
        string source_key PK
        string source
        string medium
        string campaign
    }
    DIM_PAGE {
        string page_key PK
        string page_path
        string page_title
        string content_group
    }
    DIM_ITEM {
        string item_key PK
        string item_name
        string item_category
        string item_brand
    }
    FACT_EVENTS {
        string event_id PK
        string user_pseudo_id FK
        string session_id FK
        date event_date FK
        string page_key FK
        string event_name
        timestamp event_timestamp
        int event_seq_in_session
    }
    FACT_SESSIONS {
        string session_id PK
        string user_pseudo_id FK
        date session_date FK
        string source_key FK
        timestamp session_start
        timestamp session_end
        int duration_seconds
        int event_count
        bool bounced
        bool converted
    }
    FACT_CONVERSIONS {
        string conversion_id PK
        string session_id FK
        string item_key FK
        date conversion_date FK
        float revenue
        int quantity
    }
</mermaid>
```

## Design notes

- **Grain of `fact_events`**: one row per GA4 event, post-flattening. This is
  the atomic grain — every rollup (sessions, conversions) is derived from it,
  not re-queried from raw GA4, which keeps the model auditable.
- **Grain of `fact_sessions`**: one row per session (derived via the 30-minute
  inactivity sessionisation logic in `sql/02`). Session-level measures
  (bounce rate, avg. session duration) live here so they aren't recomputed
  per-event in DAX, which would be slow and semantically wrong (context
  transition on a non-additive grain).
- **Grain of `fact_conversions`**: one row per purchased item per transaction
  — the classic "line item" fact, additive on revenue and quantity.
- Relationships are **single-direction** (dim → fact) everywhere, per Power
  BI best practice — bidirectional filtering here would create ambiguous
  paths between `fact_sessions` and `fact_conversions` through `dim_user`.
- `dim_date` is a standalone calendar table marked as the model's Date
  table, required for the time-intelligence DAX in `dax/time_intelligence_measures.dax`
  to work (`DATEADD`, `SAMEPERIODLASTYEAR`, etc. need a proper contiguous
  date dimension, not a date column pulled from the fact).
