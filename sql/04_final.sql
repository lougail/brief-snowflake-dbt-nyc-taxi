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
GROUP BY trip_date
ORDER BY trip_date;

-- Analyse par zone : une ligne par zone de départ avec volume et revenus
CREATE OR REPLACE TABLE zone_analysis AS
SELECT
    pu_location_id AS zone_id,
    COUNT(*) AS total_trips,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS popularity_pct,
    AVG(total_amount) AS avg_revenue,
    SUM(total_amount) AS total_revenue
FROM STAGING.clean_trips
GROUP BY zone_id
ORDER BY popularity_pct DESC;

-- Patterns horaires : une ligne par heure avec demande, revenus et vitesse
CREATE OR REPLACE TABLE hourly_patterns AS
SELECT
    pickup_hour,
    COUNT(*) AS total_trips,
    AVG(total_amount) AS avg_revenue,
    AVG(avg_speed_mph) AS avg_speed
FROM STAGING.clean_trips
GROUP BY pickup_hour
ORDER BY pickup_hour;