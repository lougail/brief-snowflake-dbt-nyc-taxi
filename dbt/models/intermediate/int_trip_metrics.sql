-- Enrichissement avec catégories business
SELECT
    vendor_id,
    pickup_datetime,
    dropoff_datetime,
    passenger_count,
    trip_distance,
    pu_location_id,
    do_location_id,
    payment_type,
    fare_amount,
    tip_amount,
    total_amount,
    trip_duration_min,
    pickup_hour,
    pickup_dow,
    avg_speed_mph,
    tip_percentage,

    CASE
        WHEN trip_distance <= 1 THEN 'court'
        WHEN trip_distance <= 5 THEN 'moyen'
        WHEN trip_distance <= 10 THEN 'long'
        ELSE 'tres_long'
    END AS distance_category,

    CASE
        WHEN pickup_hour BETWEEN 6 AND 9 THEN 'rush_matinal'
        WHEN pickup_hour BETWEEN 10 AND 15 THEN 'journee'
        WHEN pickup_hour BETWEEN 16 AND 19 THEN 'rush_soir'
        WHEN pickup_hour BETWEEN 20 AND 23 THEN 'soiree'
        ELSE 'nuit'
    END AS time_period,

    CASE
        WHEN pickup_dow IN (6, 7) THEN 'weekend'
        ELSE 'semaine'
    END AS day_type
FROM {{ ref('stg_yellow_taxi_trips') }}
