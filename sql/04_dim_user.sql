-- =============================================================================
-- 04_dim_user.sql
--
-- Purpose : One row per user_pseudo_id, with first-touch attribution and
--           the device/geo attributes captured at their first-seen event.
--           SCD Type 1 (overwrite) — acceptable here since device/geo drift
--           per user is noise, not a dimension worth tracking history for.
--           Documented as a deliberate simplification, not an oversight.
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.dim_user` AS

WITH first_touch AS (
    SELECT
        user_pseudo_id,
        event_timestamp,
        device_category,
        geo_country,
        traffic_source_source,
        traffic_source_medium,
        ROW_NUMBER() OVER (
            PARTITION BY user_pseudo_id ORDER BY event_timestamp ASC
        ) AS rn
    FROM `ga4_dw.stg_ga4_events_flat`
)

SELECT
    user_pseudo_id,
    DATE(event_timestamp) AS first_seen_date,
    device_category,
    geo_country,
    traffic_source_source AS acquisition_source,
    traffic_source_medium AS acquisition_medium,
    CASE
        WHEN traffic_source_medium IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
        WHEN traffic_source_medium = 'organic' THEN 'Organic Search'
        WHEN traffic_source_medium = 'referral' THEN 'Referral'
        WHEN traffic_source_medium = '(none)' OR traffic_source_medium IS NULL THEN 'Direct'
        ELSE 'Other'
    END AS acquisition_channel
FROM first_touch
WHERE rn = 1;
