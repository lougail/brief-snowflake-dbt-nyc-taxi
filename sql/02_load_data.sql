-- ============================================
-- 02_load_data.sql
-- Chargement des fichiers Parquet dans la table RAW
-- ============================================

USE WAREHOUSE NYC_TAXI_WH;
USE DATABASE NYC_TAXI_DB;
USE SCHEMA RAW;

-- File format Parquet optimisé
-- USE_VECTORIZED_SCANNER : chargement 80% plus rapide
-- USE_LOGICAL_TYPE : conversion automatique des timestamps
CREATE OR REPLACE FILE FORMAT parquet_format
    TYPE = PARQUET
    USE_VECTORIZED_SCANNER = TRUE
    USE_LOGICAL_TYPE = TRUE;

-- Table RAW avec noms normalisés en snake_case
CREATE OR REPLACE TABLE yellow_taxi_trips (
    vendor_id                NUMBER,
    pickup_datetime          TIMESTAMP,
    dropoff_datetime         TIMESTAMP,
    passenger_count          NUMBER,
    trip_distance            FLOAT,
    ratecode_id              NUMBER,
    store_and_fwd_flag       VARCHAR,
    pu_location_id           NUMBER,
    do_location_id           NUMBER,
    payment_type             NUMBER,
    fare_amount              FLOAT,
    extra                    FLOAT,
    mta_tax                  FLOAT,
    tip_amount               FLOAT,
    tolls_amount             FLOAT,
    improvement_surcharge    FLOAT,
    total_amount             FLOAT,
    congestion_surcharge     FLOAT,
    airport_fee              FLOAT,
    cbd_congestion_fee       FLOAT
);

-- Chargement des 12 fichiers Parquet (2025) avec renommage des colonnes
COPY INTO yellow_taxi_trips
FROM (
    SELECT
        $1:VendorID::NUMBER,
        $1:tpep_pickup_datetime::TIMESTAMP,
        $1:tpep_dropoff_datetime::TIMESTAMP,
        $1:passenger_count::NUMBER,
        $1:trip_distance::FLOAT,
        $1:RatecodeID::NUMBER,
        $1:store_and_fwd_flag::VARCHAR,
        $1:PULocationID::NUMBER,
        $1:DOLocationID::NUMBER,
        $1:payment_type::NUMBER,
        $1:fare_amount::FLOAT,
        $1:extra::FLOAT,
        $1:mta_tax::FLOAT,
        $1:tip_amount::FLOAT,
        $1:tolls_amount::FLOAT,
        $1:improvement_surcharge::FLOAT,
        $1:total_amount::FLOAT,
        $1:congestion_surcharge::FLOAT,
        $1:Airport_fee::FLOAT,
        $1:cbd_congestion_fee::FLOAT
    FROM @nyc_taxi_internal_stage
)
FILE_FORMAT = (FORMAT_NAME = 'parquet_format');