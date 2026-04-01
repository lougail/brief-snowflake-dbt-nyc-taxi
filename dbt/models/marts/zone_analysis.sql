-- Analyse par zone : une ligne par zone de départ
SELECT
    pu_location_id AS zone_id,
    COUNT(*) AS total_trips,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS popularity_pct,
    AVG(total_amount) AS avg_revenue,
    SUM(total_amount) AS total_revenue
FROM {{ ref('int_trip_metrics') }}
GROUP BY zone_id
