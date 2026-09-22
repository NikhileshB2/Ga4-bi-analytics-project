-- =============================================================================
-- 07_fact_conversions.sql
--
-- Purpose : Line-item grain conversion fact — one row per item per
--           purchase event. Fully additive on revenue and quantity, which
--           is what you want for a fact table (SUM-safe from any angle,
--           no double-counting risk in DAX).
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.fact_conversions` AS

SELECT
    TO_HEX(MD5(CONCAT(i.event_id, '-', COALESCE(i.item_id, '')))) AS conversion_id,
    s.session_id,
    TO_HEX(MD5(COALESCE(i.item_id, ''))) AS item_key,
    i.event_date AS conversion_date,
    i.item_revenue AS revenue,
    i.quantity
FROM `ga4_dw.stg_ga4_events_items` i
JOIN `ga4_dw.stg_sessionized_events` s
  ON i.event_id = s.event_id
WHERE i.event_name = 'purchase';
