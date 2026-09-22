# Paginated Report Spec — Monthly Executive Revenue Statement

Built in **Power BI Report Builder** against the same semantic model
(connect via "Power BI semantic model" data source in Report Builder, not a
fresh BigQuery connection — this proves paginated and interactive reports
share one governed model instead of drifting apart).

## Why a paginated report here, not an interactive Power BI report

Interactive reports render everything client-side and are built to be
*explored*. Paginated reports are built to be **printed or emailed as a
PDF** and render pixel-identically every time, on any page size — exactly
what finance wants for a monthly statement that goes into an audit folder
or gets emailed to executives who never open Power BI. The differentiator
is fixed layout + tablix pagination, not visuals.

## Report structure

**Page setup**: A4, portrait, 1cm margins, header/footer repeated on every
page (`RepeatOnNewPage = True` on the header row group).

```
┌──────────────────────────────────────────────────┐
│ [Logo]     Monthly Revenue Statement    [Page X/Y]│  ← Header (repeats)
│            Period: =Parameters!ReportMonth.Value  │
├──────────────────────────────────────────────────┤
│  KPI strip (4 textboxes, single row):             │
│   Total Revenue | Sessions | Conv. Rate | AOV     │
├──────────────────────────────────────────────────┤
│  Tablix: Revenue by Channel                       │
│   Row group: dim_traffic_source[medium]           │
│   Column group: dim_date[month_name] (last 3 mo)  │
│   Detail: SUM(fact_conversions[revenue])          │
│   Subtotal row per channel, grand total row        │
├──────────────────────────────────────────────────┤
│  Tablix: Top 20 Products by Revenue               │
│   Row group: dim_item[item_name]                  │
│   Sort: revenue DESC, static top-N filter          │
│   Page break: none (fits one page by design)      │
├──────────────────────────────────────────────────┤
│ Generated =Globals!ExecutionTime  |  Confidential  │  ← Footer (repeats)
└──────────────────────────────────────────────────┘
```

## Parameters

| Parameter | Type | Purpose |
|---|---|---|
| `ReportMonth` | Date, single-select, default = last complete month | Drives the header label and the query filter |
| `Region` | Text, multi-select, "(All)" default | Optional slicer passed into the underlying DAX query as a filter |

## Data-driven subscription

Configured to run on the 1st business day of each month, `ReportMonth`
auto-populated to "previous month," output as PDF, emailed to a
distribution list — this is the automation the requirement means by
"export automation for pixel-accurate PDF output." Set up under
**Subscribe > Data-driven subscription** in the Power BI Service (Premium
capacity required for paginated report subscriptions).

## Pixel-accuracy checklist (what makes this "pixel-accurate," specifically)

- All measurements in the RDL use `cm`, not `in` or auto-sizing, so the
  same report prints identically regardless of the machine's regional
  print settings.
- Tablix column widths are fixed, not `Auto`, so column boundaries don't
  shift with content length between refreshes.
- `KeepTogether = True` on each tablix group instance so a channel's row
  group never splits mid-way across a page break.
- Fonts embedded / restricted to ones guaranteed present on the rendering
  server (Segoe UI), since a substituted fallback font silently breaks
  pixel alignment.
