-- =============================================================================
-- 02_sessionization.sql
--
-- Purpose : Derive session boundaries from the flattened event stream.
--
-- GA4 gives you ga_session_id already, but it's not always reliable across
-- exports/timezones and it's a good interview talking point to show you can
-- derive it yourself from first principles (the classic 30-minute
-- inactivity rule), then cross-check against GA4's own session id.
-- =============================================================================

CREATE OR REPLACE VIEW `ga4_dw.stg_sessionized_events` AS

WITH ordered_events AS (
    SELECT
        event_id,
        user_pseudo_id,
        event_date,
        event_timestamp,
        event_name,
        page_location,
        ga_session_id,
        LAG(event_timestamp) OVER (
            PARTITION BY user_pseudo_id
            ORDER BY event_timestamp
        ) AS prev_event_timestamp
    FROM `ga4_dw.stg_ga4_events_flat`
),

session_breaks AS (
    SELECT
        *,
        -- new session starts when gap since previous event > 30 minutes,
        -- or this is the user's first event ever
        CASE
            WHEN prev_event_timestamp IS NULL THEN 1
            WHEN TIMESTAMP_DIFF(event_timestamp, prev_event_timestamp, MINUTE) > 30 THEN 1
            ELSE 0
        END AS is_new_session
    FROM ordered_events
),

session_numbered AS (
    SELECT
        *,
        SUM(is_new_session) OVER (
            PARTITION BY user_pseudo_id
            ORDER BY event_timestamp
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS derived_session_seq
    FROM session_breaks
)

SELECT
    event_id,
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    page_location,
    ga_session_id,
    -- deterministic session_id: user + derived sequence number, independent
    -- of GA4's own id so it's stable even if ga_session_id is null/noisy
    CONCAT(user_pseudo_id, '-', CAST(derived_session_seq AS STRING)) AS session_id,
    derived_session_seq,
    ROW_NUMBER() OVER (
        PARTITION BY user_pseudo_id, derived_session_seq
        ORDER BY event_timestamp
    ) AS event_seq_in_session
FROM session_numbered;
