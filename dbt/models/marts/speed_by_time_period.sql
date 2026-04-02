-- Vitesse moyenne et distance par période horaire
SELECT
    time_period,
    COUNT(*) AS total_trips,
    AVG(avg_speed_mph) AS avg_speed,
    AVG(trip_distance) AS avg_distance,
    AVG(trip_duration_min) AS avg_duration_min
FROM {{ ref('int_trip_metrics') }}
GROUP BY time_period
