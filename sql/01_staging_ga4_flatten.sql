-- =============================================================================
-- 01_staging_ga4_flatten.sql
--
-- Purpose : Flatten the raw GA4 BigQuery export (one row per event, with
--           nested/repeated STRUCT/ARRAY columns for event_params, items,
--           and user_properties) into an analyst-friendly staging table.
--
-- Source  : bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*
--           (daily-sharded tables — events_20201101, events_20201102, ...)
--
-- Cost/perf notes:
--   - GA4 export tables are sharded by day AND partitioned internally by
--     event_timestamp. Always filter on the _TABLE_SUFFIX wildcard AND the
--     partition column together — filtering on suffix alone still scans
--     full table metadata; combining both lets BigQuery prune partitions.
--   - UNNEST on event_params is a CROSS JOIN — this fans out rows. Keep the
--     flatten step in its own staging view so downstream facts aren't
--     paying that fan-out cost more than once.
--   - Never SELECT * against the raw export: it's wide (100+ nested
--     fields) and you'll pay for bytes scanned on columns you don't use.
--     BigQuery is columnar — list only what you need.
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.stg_ga4_events_flat` AS

SELECT
    -- surrogate row id: GA4 has no natural event PK, so synthesize one
    TO_HEX(MD5(CONCAT(
        CAST(event_timestamp AS STRING), '-', user_pseudo_id, '-', event_name,
        '-', CAST(event_bundle_sequence_id AS STRING)
    ))) AS event_id,

    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp,
    event_name,
    event_bundle_sequence_id,

    -- device / geo (already scalar structs, no UNNEST needed)
    device.category AS device_category,
    device.operating_system AS device_os,
    geo.country AS geo_country,
    geo.region AS geo_region,

    -- traffic source (scalar struct)
    traffic_source.source AS traffic_source_source,
    traffic_source.medium AS traffic_source_medium,
    traffic_source.name AS traffic_source_campaign,

    -- key event_params, pulled out individually rather than left nested —
    -- this is the pattern for the handful of params you actually query on
    (SELECT value.string_value FROM UNNEST(event_params)
       WHERE key = 'page_location') AS page_location,
    (SELECT value.string_value FROM UNNEST(event_params)
       WHERE key = 'page_title') AS page_title,
    (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_number') AS ga_session_number,
    (SELECT value.double_value FROM UNNEST(event_params)
       WHERE key = 'value') AS event_value,

    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20201130';


-- -----------------------------------------------------------------------------
-- A second view specifically for the items array, kept SEPARATE from the
-- event-grain view above. Flattening items inline into stg_ga4_events_flat
-- would silently duplicate every non-ecommerce event's other columns by the
-- item count (or by 1 via a LEFT JOIN UNNEST) — better to model item-level
-- detail as its own fan-out, joined back only where needed (fact_conversions).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW `ga4_dw.stg_ga4_events_items` AS

SELECT
    TO_HEX(MD5(CONCAT(
        CAST(event_timestamp AS STRING), '-', user_pseudo_id, '-', event_name,
        '-', CAST(event_bundle_sequence_id AS STRING)
    ))) AS event_id,
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    event_name,
    item.item_id,
    item.item_name,
    item.item_category,
    item.item_brand,
    item.price,
    item.quantity,
    item.item_revenue

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
UNNEST(items) AS item
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20201130'
  AND event_name IN ('purchase', 'add_to_cart', 'view_item', 'begin_checkout');
