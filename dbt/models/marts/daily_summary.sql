-- Résumé quotidien : une ligne par jour
SELECT
    DATE(pickup_datetime) AS trip_date,
    COUNT(*) AS total_trips,
    AVG(trip_distance) AS avg_distance,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_revenue,
    AVG(trip_duration_min) AS avg_duration_min
FROM {{ ref('int_trip_metrics') }}
GROUP BY trip_date
