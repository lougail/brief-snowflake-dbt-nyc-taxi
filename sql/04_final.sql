-- ============================================
-- 04_final.sql
-- Tables d'analyse finale
-- ============================================

USE WAREHOUSE NYC_TAXI_WH;
USE DATABASE NYC_TAXI_DB;
USE SCHEMA FINAL;

-- Résumé quotidien : une ligne par jour avec les métriques clés
CREATE OR REPLACE TABLE daily_summary AS
SELECT
    DATE(pickup_datetime) AS trip_date,
    COUNT(*) AS total_trips,
    AVG(trip_distance) AS avg_distance,
    SUM(total_amount) AS total_revenue,
    AVG(total_amount) AS avg_revenue,
    AVG(trip_duration_min) AS avg_duration_min
FROM STAGING.clean_trips
GROUP BY trip_date;

-- Analyse par zone : une ligne par zone de départ avec volume et revenus
CREATE OR REPLACE TABLE zone_analysis AS
SELECT
    pu_location_id AS zone_id,
    COUNT(*) AS total_trips,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS popularity_pct,
    AVG(total_amount) AS avg_revenue,
    SUM(total_amount) AS total_revenue
FROM STAGING.clean_trips
GROUP BY zone_id;

-- Patterns horaires : une ligne par heure avec demande, revenus et vitesse
CREATE OR REPLACE TABLE hourly_patterns AS
SELECT
    pickup_hour,
    COUNT(*) AS total_trips,
    AVG(total_amount) AS avg_revenue,
    AVG(avg_speed_mph) AS avg_speed
FROM STAGING.clean_trips
GROUP BY pickup_hour;

-- Table de faits : un enregistrement par trajet
CREATE OR REPLACE TABLE fact_trips AS
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
FROM STAGING.clean_trips;

-- Revenu par jour de la semaine
CREATE OR REPLACE TABLE revenue_by_day_of_week AS
SELECT
    pickup_dow,
    CASE WHEN pickup_dow IN (6, 7) THEN 'weekend' ELSE 'semaine' END AS day_type,
    COUNT(*) AS total_trips,
    AVG(total_amount) AS avg_revenue,
    SUM(total_amount) AS total_revenue,
    AVG(tip_percentage) AS avg_tip_pct
FROM STAGING.clean_trips
GROUP BY pickup_dow;

-- Pourboire par mode de paiement
CREATE OR REPLACE TABLE tips_by_payment_type AS
SELECT
    payment_type,
    CASE
        WHEN payment_type = 1 THEN 'Carte'
        WHEN payment_type = 2 THEN 'Cash'
        WHEN payment_type = 3 THEN 'Gratuit'
        WHEN payment_type = 4 THEN 'Litige'
        ELSE 'Autre'
    END AS payment_label,
    COUNT(*) AS total_trips,
    AVG(tip_amount) AS avg_tip,
    AVG(tip_percentage) AS avg_tip_pct,
    SUM(tip_amount) AS total_tips
FROM STAGING.clean_trips
GROUP BY payment_type;

-- Vitesse par période horaire
CREATE OR REPLACE TABLE speed_by_time_period AS
SELECT
    CASE
        WHEN pickup_hour BETWEEN 6 AND 9 THEN 'rush_matinal'
        WHEN pickup_hour BETWEEN 10 AND 15 THEN 'journee'
        WHEN pickup_hour BETWEEN 16 AND 19 THEN 'rush_soir'
        WHEN pickup_hour BETWEEN 20 AND 23 THEN 'soiree'
        ELSE 'nuit'
    END AS time_period,
    COUNT(*) AS total_trips,
    AVG(avg_speed_mph) AS avg_speed,
    AVG(trip_distance) AS avg_distance,
    AVG(trip_duration_min) AS avg_duration_min
FROM STAGING.clean_trips
GROUP BY time_period;
