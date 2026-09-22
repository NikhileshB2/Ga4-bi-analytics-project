-- =============================================================================
-- 06_fact_events_and_sessions.sql
--
-- Purpose : The two core fact tables at their respective grains.
--
-- fact_events    : one row per event (atomic grain)
-- fact_sessions  : one row per session (aggregated grain, computed once
--                  here rather than left to DAX — session-level facts like
--                  bounce/duration are non-additive across their own
--                  member events, so they must be pre-aggregated in SQL,
--                  not computed via a DAX measure that iterates events).
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.fact_events` AS

SELECT
    e.event_id,
    e.user_pseudo_id,
    s.session_id,
    e.event_date,
    e.event_timestamp,
    e.event_name,
    TO_HEX(MD5(COALESCE(e.page_location, ''))) AS page_key,
    s.event_seq_in_session,
    e.event_value,
    e.transaction_id
FROM `ga4_dw.stg_ga4_events_flat` e
JOIN `ga4_dw.stg_sessionized_events` s
  ON e.event_id = s.event_id;


CREATE OR REPLACE VIEW `ga4_dw.fact_sessions` AS

WITH session_agg AS (
    SELECT
        s.session_id,
        s.user_pseudo_id,
        MIN(s.event_date) AS session_date,
        MIN(s.event_timestamp) AS session_start,
        MAX(s.event_timestamp) AS session_end,
        COUNT(*) AS event_count,
        COUNTIF(e.event_name = 'purchase') > 0 AS converted,
        -- landing page = first event's page → traffic source recorded there
        ARRAY_AGG(e.traffic_source_source ORDER BY s.event_timestamp ASC LIMIT 1)[OFFSET(0)] AS landing_source,
        ARRAY_AGG(e.traffic_source_medium ORDER BY s.event_timestamp ASC LIMIT 1)[OFFSET(0)] AS landing_medium,
        ARRAY_AGG(e.traffic_source_campaign ORDER BY s.event_timestamp ASC LIMIT 1)[OFFSET(0)] AS landing_campaign
    FROM `ga4_dw.stg_sessionized_events` s
    JOIN `ga4_dw.stg_ga4_events_flat` e ON s.event_id = e.event_id
    GROUP BY s.session_id, s.user_pseudo_id
)

SELECT
    session_id,
    user_pseudo_id,
    session_date,
    session_start,
    session_end,
    TIMESTAMP_DIFF(session_end, session_start, SECOND) AS duration_seconds,
    event_count,
    (event_count = 1) AS bounced,
    converted,
    TO_HEX(MD5(CONCAT(
        COALESCE(landing_source, ''), '-',
        COALESCE(landing_medium, ''), '-',
        COALESCE(landing_campaign, '')
    ))) AS source_key
FROM session_agg;
