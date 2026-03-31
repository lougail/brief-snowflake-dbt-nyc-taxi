-- Patterns horaires : une ligne par heure
SELECT
    pickup_hour,
    COUNT(*) AS total_trips,
    AVG(total_amount) AS avg_revenue,
    AVG(avg_speed_mph) AS avg_speed
FROM {{ ref('int_trip_metrics') }}
GROUP BY pickup_hour
ORDER BY pickup_hour
