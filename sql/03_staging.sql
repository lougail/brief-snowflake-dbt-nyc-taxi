-- ============================================
-- 03_staging.sql
-- Nettoyage et enrichissement des données
-- ============================================

USE WAREHOUSE NYC_TAXI_WH;
USE DATABASE NYC_TAXI_DB;
USE SCHEMA STAGING;

-- Table nettoyée avec métriques calculées
-- Filtres : montants positifs, distances cohérentes, zones non NULL, dates logiques
CREATE OR REPLACE TABLE clean_trips AS
WITH base AS (
    SELECT
        *,
        TIMESTAMPDIFF(MINUTE, pickup_datetime, dropoff_datetime) AS trip_duration_min
    FROM RAW.yellow_taxi_trips
    WHERE fare_amount >= 0
        AND total_amount >= 0
        AND trip_distance BETWEEN 0.1 AND 100
        AND pu_location_id IS NOT NULL
        AND do_location_id IS NOT NULL
        AND pickup_datetime < dropoff_datetime
)
SELECT
    *,
    EXTRACT(HOUR FROM pickup_datetime) AS pickup_hour,
    DAYOFWEEK(pickup_datetime) AS pickup_dow,
    EXTRACT(MONTH FROM pickup_datetime) AS pickup_month,
    DIV0NULL(trip_distance, trip_duration_min / 60) AS avg_speed_mph,
    CASE WHEN fare_amount > 0 THEN (tip_amount / fare_amount) * 100 ELSE 0 END AS tip_percentage
FROM base;