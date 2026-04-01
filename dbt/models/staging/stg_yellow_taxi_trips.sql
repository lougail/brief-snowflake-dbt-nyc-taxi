-- Nettoyage des données brutes
-- Filtres : montants positifs, distances cohérentes, zones non NULL, dates logiques, vitesse réaliste
WITH base AS (
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
        TIMESTAMPDIFF(MINUTE, pickup_datetime, dropoff_datetime) AS trip_duration_min
    FROM {{ source('raw', 'yellow_taxi_trips') }}
    WHERE fare_amount >= 0
        AND total_amount >= 0
        AND trip_distance BETWEEN 0.1 AND 100
        AND pu_location_id IS NOT NULL
        AND do_location_id IS NOT NULL
        AND pickup_datetime < dropoff_datetime
        AND TIMESTAMPDIFF(MINUTE, pickup_datetime, dropoff_datetime) >= 1
),
enriched AS (
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
        EXTRACT(HOUR FROM pickup_datetime) AS pickup_hour,
        DAYOFWEEKISO(pickup_datetime) AS pickup_dow,
        DIV0NULL(trip_distance, trip_duration_min / 60) AS avg_speed_mph,
        CASE WHEN fare_amount > 0 THEN (tip_amount / fare_amount) * 100 ELSE 0 END AS tip_percentage
    FROM base
)
SELECT *
FROM enriched
WHERE avg_speed_mph <= 120 OR avg_speed_mph IS NULL
