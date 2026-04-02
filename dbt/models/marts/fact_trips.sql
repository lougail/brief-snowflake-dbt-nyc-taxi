-- Table de faits : un enregistrement par trajet avec toutes les métriques
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
    distance_category,
    time_period,
    day_type
FROM {{ ref('int_trip_metrics') }}
