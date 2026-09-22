-- =============================================================================
-- 05_dim_traffic_source_and_item.sql
--
-- Purpose : Remaining small conformed dimensions — traffic source, page,
--           and item. Kept low-cardinality by design so they compress well
--           in Power BI's VertiPaq engine (dictionary encoding rewards
--           dimensions with far fewer distinct values than the fact).
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.dim_traffic_source` AS
SELECT DISTINCT
    TO_HEX(MD5(CONCAT(
        COALESCE(traffic_source_source, ''), '-',
        COALESCE(traffic_source_medium, ''), '-',
        COALESCE(traffic_source_campaign, '')
    ))) AS source_key,
    COALESCE(traffic_source_source, '(not set)') AS source,
    COALESCE(traffic_source_medium, '(not set)') AS medium,
    COALESCE(traffic_source_campaign, '(not set)') AS campaign
FROM `ga4_dw.stg_ga4_events_flat`;


CREATE OR REPLACE VIEW `ga4_dw.dim_page` AS
SELECT DISTINCT
    TO_HEX(MD5(COALESCE(page_location, ''))) AS page_key,
    page_location AS page_path,
    page_title,
    CASE
        WHEN page_location LIKE '%/product/%' THEN 'Product'
        WHEN page_location LIKE '%/cart%' THEN 'Cart'
        WHEN page_location LIKE '%/checkout%' THEN 'Checkout'
        WHEN page_location = '/' OR page_location LIKE '%/home%' THEN 'Home'
        ELSE 'Other'
    END AS content_group
FROM `ga4_dw.stg_ga4_events_flat`
WHERE page_location IS NOT NULL;


CREATE OR REPLACE VIEW `ga4_dw.dim_item` AS
SELECT DISTINCT
    TO_HEX(MD5(COALESCE(item_id, ''))) AS item_key,
    item_id,
    item_name,
    item_category,
    item_brand
FROM `ga4_dw.stg_ga4_events_items`
WHERE item_id IS NOT NULL;
