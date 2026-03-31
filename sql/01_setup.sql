-- ============================================
-- 01_setup.sql
-- Configuration initiale de l'infrastructure Snowflake
-- ============================================

-- Création du warehouse (ressource de calcul)
-- MEDIUM = puissance moyenne, AUTO_SUSPEND = s'éteint après 60s d'inactivité
CREATE WAREHOUSE IF NOT EXISTS NYC_TAXI_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60;

-- Création de la base de données principale
CREATE DATABASE IF NOT EXISTS NYC_TAXI_DB;

USE DATABASE NYC_TAXI_DB;

-- Création des 3 schémas (couches du data warehouse)
-- RAW : données brutes importées telles quelles
-- STAGING : données nettoyées et transformées
-- FINAL : tables prêtes pour l'analyse
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS FINAL;

-- Création du stage interne pour uploader les fichiers Parquet
USE SCHEMA RAW;

CREATE STAGE IF NOT EXISTS nyc_taxi_internal_stage
    FILE_FORMAT = (TYPE = PARQUET);