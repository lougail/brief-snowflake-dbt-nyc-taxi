-- Revenu et volume par jour de la semaine (1=lundi, 7=dimanche)
SELECT
    pickup_dow,
    day_type,
    COUNT(*) AS total_trips,
    AVG(total_amount) AS avg_revenue,
    SUM(total_amount) AS total_revenue,
    AVG(tip_percentage) AS avg_tip_pct
FROM {{ ref('int_trip_metrics') }}
GROUP BY pickup_dow, day_type
