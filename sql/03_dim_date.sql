-- =============================================================================
-- 03_dim_date.sql
--
-- Purpose : Standalone, contiguous calendar dimension. Required as the
--           model's marked "Date table" in Power BI for DAX time
--           intelligence functions (DATEADD, SAMEPERIODLASTYEAR, TOTALYTD)
--           to behave correctly — they need a contiguous date range, not
--           just the distinct dates that happen to appear in the fact.
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.dim_date` AS

WITH date_spine AS (
    SELECT date_key
    FROM UNNEST(
        GENERATE_DATE_ARRAY('2020-01-01', '2021-12-31', INTERVAL 1 DAY)
    ) AS date_key
)

SELECT
    date_key,
    EXTRACT(YEAR FROM date_key) AS year,
    EXTRACT(QUARTER FROM date_key) AS quarter,
    FORMAT_DATE('Q%Q %Y', date_key) AS quarter_label,
    EXTRACT(MONTH FROM date_key) AS month,
    FORMAT_DATE('%B', date_key) AS month_name,
    FORMAT_DATE('%Y-%m', date_key) AS year_month,
    EXTRACT(ISOWEEK FROM date_key) AS iso_week,
    FORMAT_DATE('%A', date_key) AS day_name,
    EXTRACT(DAYOFWEEK FROM date_key) AS day_of_week_num,
    EXTRACT(DAYOFWEEK FROM date_key) IN (1, 7) AS is_weekend,
    -- fiscal year starting July 1 — swap to suit whichever org this is for;
    -- documented here on purpose since "which fiscal calendar" is exactly
    -- the kind of ambiguous requirement this role has to resolve
    DATE_ADD(date_key, INTERVAL CASE WHEN EXTRACT(MONTH FROM date_key) >= 7 THEN 0 ELSE -1 END YEAR) AS fiscal_year_start
FROM date_spine;
