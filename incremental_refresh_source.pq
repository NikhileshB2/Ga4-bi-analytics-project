// =============================================================================
// incremental_refresh_source.pq
//
// Power Query M for `fact_events`, set up for Power BI incremental refresh.
//
// Setup in Power BI Desktop:
//   1. Create two Date/Time parameters named exactly RangeStart and RangeEnd
//      (Home > Manage Parameters). Default values don't matter — the
//      refresh policy overrides them at publish time.
//   2. Paste this query in as the source for `fact_events`.
//   3. Right-click the query > Incremental Refresh, and set:
//        Archive data starting:  3 years before refresh date
//        Incrementally refresh data starting: 1 month before refresh date
//        Detect data changes: off (GA4 export is append-only, immutable
//          once landed — no need to pay for change detection)
//        Only refresh complete days: on
//   4. The M engine will substitute RangeStart/RangeEnd into the WHERE
//      predicate below at each refresh, and — critically — because the
//      filter is pushed to a native BigQuery query (query folding), only
//      the changed partition is actually scanned/billed, not the whole
//      table. Confirm folding held with View Native Query before shipping.
// =============================================================================

let
    Source = GoogleBigQuery.Database(),
    ga4_dw = Source{[Name="ga4_dw"]}[Data],

    fact_events_table = ga4_dw{[Name="fact_events"]}[Data],

    // Query-folded filter — becomes part of the native SQL sent to
    // BigQuery, not a client-side filter, so partition pruning still works.
    FilteredRows = Table.SelectRows(
        fact_events_table,
        each [event_date] >= Date.From(RangeStart)
         and [event_date] < Date.From(RangeEnd)
    ),

    // Explicit typing — avoids Power Query's "Change Type" step firing an
    // extra, potentially fold-breaking query on top of the filter.
    TypedRows = Table.TransformColumnTypes(
        FilteredRows,
        {
            {"event_id", type text},
            {"user_pseudo_id", type text},
            {"session_id", type text},
            {"event_date", type date},
            {"event_timestamp", type datetimezone},
            {"event_name", type text},
            {"page_key", type text},
            {"event_seq_in_session", Int64.Type},
            {"event_value", type number},
            {"transaction_id", type text}
        }
    )
in
    TypedRows
