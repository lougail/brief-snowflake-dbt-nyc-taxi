# Comprendre l'architecture Snowflake

## Le problème que Snowflake résout

Dans une base de données classique (PostgreSQL, MySQL…), **le calcul et le stockage sont sur la même machine**. Si ta requête est lente, tu dois upgrader toute la machine — même si c'est juste le CPU qui manque et que tu as plein de stockage libre.

Snowflake sépare les deux. Tu peux augmenter la puissance de calcul sans toucher au stockage, et inversement. C'est le coeur de son architecture.

---

## Les 3 couches

Snowflake repose sur **3 couches indépendantes** qui ne se mélangent jamais :

```
┌─────────────────────────────────────────────┐
│           CLOUD SERVICES                    │
│  (authentification, optimisation, sécurité) │
├─────────────────────────────────────────────┤
│              COMPUTE                        │
│     (warehouses = puissance de calcul)      │
├─────────────────────────────────────────────┤
│              STORAGE                        │
│    (données stockées, gérées par Snowflake) │
└─────────────────────────────────────────────┘
```

### Couche Storage

C'est là que les données vivent physiquement. Snowflake les stocke dans un format compressé et optimisé en interne (sur S3, Azure Blob ou GCS selon ton cloud provider). **Tu n'interagis jamais directement avec cette couche** — tu passes toujours par du SQL.

Point important : les données persistent indépendamment de tout le reste. Si tu éteins tous tes warehouses, tes données sont toujours là.

### Couche Compute (les Warehouses)

Un **warehouse** c'est un cluster de machines virtuelles qui exécutent tes requêtes. C'est **uniquement** de la puissance de calcul (CPU + RAM). Il ne stocke rien de permanent.

Caractéristiques clés :
- **Taille configurable** : de `X-SMALL` à `6X-LARGE`, chaque taille double les ressources (et le coût) par rapport à la précédente
- **Auto-suspend** : le warehouse s'éteint automatiquement après X secondes d'inactivité (= plus de facturation)
- **Auto-resume** : il redémarre automatiquement quand une requête arrive
- **Isolation** : plusieurs warehouses peuvent lire les mêmes données en même temps sans interférence. L'équipe data peut lancer des transformations lourdes pendant que l'équipe analytics fait ses dashboards, sans se gêner

```sql
CREATE WAREHOUSE NYC_TAXI_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60        -- s'éteint après 60s d'inactivité
    AUTO_RESUME = TRUE;      -- redémarre automatiquement
```

> **Analogie** : le warehouse c'est le moteur d'une voiture. Sans moteur, la voiture ne bouge pas, mais le coffre (storage) garde tes affaires même moteur éteint.

### Couche Cloud Services

C'est le "cerveau" de Snowflake. Cette couche gère :
- L'authentification et le contrôle d'accès
- L'optimisation des requêtes (query planning)
- La gestion des métadonnées (quelles tables existent, combien de lignes, etc.)
- Le chiffrement des données

Tu n'interagis pas directement avec cette couche non plus — elle travaille en arrière-plan.

---

## L'organisation logique des données

Maintenant qu'on sait où les données vivent (storage) et ce qui les traite (compute), voyons comment elles sont **organisées**.

La hiérarchie est simple :

```
Account
  └── Database
        └── Schema
              ├── Table
              ├── View
              ├── Stage
              ├── File Format
              ├── Stream
              ├── Task
              ├── Pipe
              ├── Sequence
              ├── Stored Procedure
              └── UDF
```

### Database

Le conteneur de plus haut niveau dans un compte Snowflake. C'est un regroupement logique — un peu comme un dossier racine.

```sql
CREATE DATABASE NYC_TAXI_DB;
```

### Schema

Une sous-division à l'intérieur d'une database. Sert à **organiser les objets par usage ou par étape**. Par exemple, dans un pipeline de données classique :

```sql
CREATE SCHEMA RAW;       -- données brutes telles qu'importées
CREATE SCHEMA STAGING;   -- données nettoyées / transformées
CREATE SCHEMA FINAL;     -- données prêtes pour l'analyse
```

Un schema contient **tous les types d'objets** décrits ci-dessous (pas juste des tables).

---

## Les objets dans un schema

### Table

L'objet fondamental. Stocke les données en lignes et colonnes, comme dans n'importe quelle base de données relationnelle.

```sql
CREATE TABLE yellow_taxi_trips (
    vendor_id NUMBER,
    pickup_datetime TIMESTAMP,
    dropoff_datetime TIMESTAMP,
    passenger_count NUMBER,
    trip_distance FLOAT,
    total_amount FLOAT
);
```

On peut aussi créer une table **automatiquement à partir de fichiers** avec `INFER_SCHEMA` — Snowflake détecte les colonnes et leurs types depuis des fichiers Parquet ou CSV :

```sql
CREATE OR REPLACE TABLE yellow_taxi_trips
  USING TEMPLATE (
      SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
      FROM TABLE(
          INFER_SCHEMA(
              LOCATION => '@mon_stage',
              FILE_FORMAT => 'parquet_format'
          )
      )
  );
```

> C'est exactement ce que fait l'interface Snowflake quand tu charges un fichier et que "les colonnes se créent toutes seules". L'UI génère ce SQL en arrière-plan.

### View

Une requête SQL sauvegardée qui se comporte comme une table, mais **sans stocker de données**. Chaque fois que tu la requêtes, la requête sous-jacente s'exécute.

```sql
CREATE VIEW long_trips AS
  SELECT * FROM yellow_taxi_trips
  WHERE trip_distance > 20;

-- Utilisation : exactement comme une table
SELECT * FROM long_trips;
```

Utile pour : simplifier des requêtes complexes, exposer un sous-ensemble de données, masquer des colonnes sensibles.

### Stage

C'est une **zone de transit pour les fichiers** avant leur chargement dans une table. C'est l'objet qui fait le pont entre le monde des fichiers (parquet, csv, json…) et le monde des tables SQL.

Il en existe deux types :

| Type | Où sont les fichiers | Exemple |
|---|---|---|
| **Interne** | Stockés dans Snowflake (tu les uploades via `PUT` ou l'UI) | `@nyc_taxi_internal_stage` |
| **Externe** | Stockés dans un bucket cloud (S3, GCS, Azure) | `@s3://mon-bucket/data/` |

```sql
-- Stage interne (les fichiers sont uploadés dans Snowflake)
CREATE STAGE nyc_taxi_internal_stage;

-- Stage externe (pointe vers un bucket S3)
CREATE STAGE nyc_taxi_external_stage
    URL = 's3://mon-bucket/nyc-taxi-data/';
```

Le flux de chargement :
```
Fichier parquet ──upload──> Stage ──COPY INTO──> Table
```

> Le stage externe est "mieux" dans le sens où les données restent à leur emplacement d'origine et ne sont pas dupliquées. Mais ça nécessite de configurer un bucket cloud (S3, GCS…), ce qui est une étape en plus.

### File Format

Décrit **comment lire un fichier** dans un stage : quel type (parquet, csv, json), quel délimiteur, quelle compression, etc.

```sql
CREATE FILE FORMAT parquet_format
    TYPE = PARQUET
    USE_VECTORIZED_SCANNER = TRUE;

CREATE FILE FORMAT csv_format
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1;
```

Sans file format, Snowflake ne sait pas comment interpréter les fichiers dans un stage.

### Stream

Capture les **changements** (insertions, modifications, suppressions) sur une table. Fonctionne comme un journal de modifications en temps réel.

```sql
CREATE STREAM raw_changes ON TABLE yellow_taxi_trips;

-- Après des INSERT/UPDATE/DELETE sur yellow_taxi_trips,
-- le stream contient les lignes modifiées avec des métadonnées :
-- metadata$action = 'INSERT' | 'DELETE'
-- metadata$isupdate = TRUE | FALSE
SELECT * FROM raw_changes;
```

Utile pour : traitement incrémental (ne transformer que les nouvelles données au lieu de tout retraiter).

### Task

Une **tâche planifiée** qui exécute du SQL à intervalles réguliers ou quand un stream contient des données.

```sql
CREATE TASK refresh_analytics
    WAREHOUSE = NYC_TAXI_WH
    SCHEDULE = '60 minute'          -- toutes les 60 minutes
    WHEN SYSTEM$STREAM_HAS_DATA('raw_changes')  -- seulement s'il y a de nouvelles données
    AS
        INSERT INTO analytics_table
        SELECT * FROM raw_changes;
```

> **Stream + Task** forment un duo pour le traitement incrémental automatisé : le stream détecte les changements, la task les traite.

### Pipe (Snowpipe)

Chargement **automatique et continu** de fichiers depuis un stage vers une table. Dès qu'un nouveau fichier arrive dans le stage, Snowpipe le charge automatiquement.

```sql
CREATE PIPE auto_load_taxi AS
    COPY INTO yellow_taxi_trips
    FROM @nyc_taxi_internal_stage
    FILE_FORMAT = (TYPE = PARQUET);
```

Différence avec un `COPY INTO` manuel : le pipe tourne en continu et surveille le stage, alors que `COPY INTO` est une commande ponctuelle.

### Sequence

Génère des **nombres uniques auto-incrémentés**. Utile pour créer des identifiants.

```sql
CREATE SEQUENCE trip_id_seq START = 1 INCREMENT = 1;

-- Utilisation
INSERT INTO ma_table (id, data)
    VALUES (trip_id_seq.NEXTVAL, 'test');
```

### Stored Procedure

Bloc de code réutilisable stocké dans Snowflake. Peut contenir de la logique complexe en SQL, JavaScript, Python ou Java.

```sql
CREATE PROCEDURE clean_old_data(days_to_keep INT)
    RETURNS STRING
    LANGUAGE SQL
    AS
    $$
        DELETE FROM yellow_taxi_trips
        WHERE pickup_datetime < DATEADD('day', -days_to_keep, CURRENT_DATE());
        RETURN 'Nettoyage terminé';
    $$;

-- Appel
CALL clean_old_data(365);
```

### UDF (User-Defined Function)

Fonction personnalisée utilisable directement dans les requêtes SQL. Contrairement à une procédure, une UDF **retourne une valeur** et s'utilise dans un `SELECT`.

```sql
CREATE FUNCTION distance_km(miles FLOAT)
    RETURNS FLOAT
    AS
    $$ miles * 1.60934 $$;

-- Utilisation dans une requête
SELECT trip_distance, distance_km(trip_distance) AS distance_km
FROM yellow_taxi_trips;
```

---

## Résumé visuel avec un exemple concret

Voici comment tous ces composants s'assemblent dans le projet NYC Taxi :

```
NYC_TAXI_WH  ← warehouse (compute, s'éteint après 60s d'inactivité)
     │
     │  exécute les requêtes sur
     ▼
NYC_TAXI_DB  ← database
     │
     ├── RAW  ← schema (données brutes)
     │    ├── nyc_taxi_internal_stage  ← stage (fichiers parquet uploadés)
     │    ├── parquet_format           ← file format (comment lire les parquet)
     │    └── yellow_taxi_trips       ← table (12 mois de courses, ~30M lignes)
     │
     ├── STAGING  ← schema (transformations intermédiaires, géré par dbt)
     │    └── (views/tables de transformation)
     │
     └── FINAL  ← schema (données prêtes pour l'analyse)
          └── (tables/views finales pour dashboards)
```

**Le flux complet :**
```
Fichiers parquet ──upload via UI──> Stage (zone de transit)
                                      │
                              INFER_SCHEMA (détecte les colonnes)
                                      │
                              COPY INTO (charge les données)
                                      │
                                      ▼
                               Table RAW (données brutes)
                                      │
                                dbt (transformations)
                                      │
                                      ▼
                            Tables STAGING puis FINAL
```

---

## Ce qu'il faut retenir

1. **Warehouse = compute** : il exécute, il ne stocke rien. Éteins-le, tes données restent.
2. **Database > Schema > Objets** : c'est juste de l'organisation logique, comme des dossiers.
3. **Un schema contient bien plus que des tables** : stages, views, streams, tasks, pipes, etc.
4. **Le stage est le pont** entre le monde des fichiers et le monde SQL.
5. **L'UI et le SQL font la même chose** : quand l'interface "crée les colonnes automatiquement", elle exécute du `INFER_SCHEMA` + `COPY INTO` en arrière-plan.
6. **La séparation compute/storage** permet de scaler indépendamment et de ne payer le calcul que quand on l'utilise.
