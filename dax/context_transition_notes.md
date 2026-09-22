# Context Transition — Worked Example From This Model

Context transition is what happens when a **row context** gets converted
into an equivalent **filter context**, which only happens inside a
`CALCULATE` (or any measure reference, since every measure is implicitly
wrapped in one).

## Where it bites in this model

`fact_sessions[bounced]` is a boolean computed once in SQL
(`sql/06_fact_events_and_sessions.sql`) precisely to avoid needing context
transition per-row in DAX. But suppose instead it had been left to Power
BI, computed row-by-row in a calculated column:

```dax
// Calculated column on fact_sessions — DON'T do this, shown to explain why
Bounced (bad pattern) =
CALCULATE ( COUNTROWS ( fact_events ), fact_events[session_id] = fact_sessions[session_id] ) = 1
```

Here's what actually happens:

1. A calculated column evaluates **once per row of `fact_sessions`**, in a
   **row context** — you're "standing on" one session row at a time.
2. `fact_events[session_id] = fact_sessions[session_id]` can't be evaluated
   as a row filter directly because `fact_sessions[session_id]` is a row
   context reference, not a column-vs-constant filter.
3. Because this expression is wrapped in `CALCULATE`, DAX performs **context
   transition**: it takes every column value from the current row
   (`fact_sessions[session_id]` for *this* row) and turns it into an
   equivalent `FILTER`-style filter context, as if you'd written
   `CALCULATE ( ..., FILTER ( ALL ( fact_sessions ), fact_sessions[session_id] = "this row's value" ) )`.
4. `COUNTROWS ( fact_events )` is then evaluated inside that filter context
   — but `fact_events` is only filtered if there's an active relationship
   from `fact_sessions` to `fact_events` on `session_id`, which there isn't
   here (both are fact tables; no relationship between them in the star
   schema — see `architecture/star-schema-diagram.md`). Context transition
   without a relationship to propagate through just silently returns an
   unfiltered or wrong count.
5. Even where it *would* work, doing this per-row, for every row of
   `fact_sessions`, forces the formula engine to materialize a filter
   context and re-scan `fact_events` once per session — this is the classic
   "calculated column doing what SQL should have done" performance trap.

## The fix (what's actually in this model)

Compute `bounced` and `event_count` once, set-based, in SQL
(`sql/06_fact_events_and_sessions.sql`), where the engine can do it as a
single `GROUP BY` pass over `fact_events`. DAX then just reads the column —
no context transition, no per-row filter materialization, no relationship
dependency between two fact tables.

**Rule of thumb applied throughout this model:** if a calculation only
needs to look at rows *within the same grain* (session-level facts from
event-level rows), do it in SQL at load time. Reserve DAX context
transition for calculations that genuinely depend on the *current visual's
filter context* — like the time-intelligence measures in
`time_intelligence_measures.dax`, where the whole point is that the answer
changes depending on what's selected on the report canvas.

## Why this is slow, in one sentence

Context transition forces work from the columnar, multi-threaded **storage
engine** into the single-threaded **formula engine**, once per row of
context — the more rows triggering it, the more that single thread has to
do serially, which is why it shows up as a `CallbackDataID` bottleneck in
DAX Studio's Server Timings when it goes wrong.
