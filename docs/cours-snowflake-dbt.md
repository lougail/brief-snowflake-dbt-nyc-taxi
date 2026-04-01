# Cours complet : Snowflake + dbt

## Table des matières

1. [Le data warehousing moderne — contexte](#1-le-data-warehousing-moderne)
2. [Snowflake — architecture et fonctionnement](#2-snowflake)
3. [SQL sur Snowflake — spécificités](#3-sql-sur-snowflake)
4. [dbt — le framework de transformation](#4-dbt)
5. [Le pipeline complet — de la donnée brute au KPI](#5-le-pipeline-complet)
6. [Bonnes pratiques et pièges classiques](#6-bonnes-pratiques)

---

## 1. Le data warehousing moderne

### Pourquoi un data warehouse ?

Une base de données classique (PostgreSQL, MySQL) est conçue pour les **transactions** : insérer une commande, mettre à jour un profil, supprimer un message. C'est de l'**OLTP** (Online Transaction Processing) — beaucoup de petites opérations rapides.

Mais quand tu veux analyser des données — "quel est le revenu moyen par zone sur les 12 derniers mois ?" — tu scannes des millions de lignes. Sur une base OLTP, cette requête :
- Bloque les transactions en cours
- Est lente (les données sont organisées par ligne, pas par colonne)
- Ne scale pas (tu ne peux pas juste "ajouter du CPU")

Un **data warehouse** est conçu pour l'**OLAP** (Online Analytical Processing) :
- Optimisé pour les lectures massives (scans de millions de lignes)
- Stockage en colonnes (columnar) — plus efficace pour les agrégations
- Séparation compute/storage — tu scales indépendamment

### Les architectures de données

**ETL classique (Extract, Transform, Load)**
```
Sources → Transformation (serveur ETL) → Data Warehouse
```
On transforme AVANT de charger. Problème : si ta transformation a un bug, tu dois tout recharger.

**ELT moderne (Extract, Load, Transform)**
```
Sources → Data Warehouse (brut) → Transformation (dans le warehouse)
```
On charge d'abord les données brutes, on transforme ensuite DANS le warehouse. C'est ce qu'on fait avec Snowflake + dbt.

Avantages de l'ELT :
- Les données brutes sont toujours disponibles (on peut retransformer)
- Le warehouse a la puissance de calcul pour transformer
- Séparation des responsabilités : le chargement et la transformation sont indépendants

### La convention des couches (RAW → STAGING → FINAL)

C'est un pattern universel en data engineering :

| Couche | Autre nom courant | Rôle | Qui y touche |
|--------|-------------------|------|--------------|
| **RAW** | Bronze, Landing | Données brutes, exactement comme reçues | Personne (en lecture seule) |
| **STAGING** | Silver, Cleaned | Données nettoyées, typées, validées | Data engineers |
| **FINAL** | Gold, Marts | Tables agrégées prêtes pour l'analyse | Analystes, BI tools |

**Pourquoi ne pas transformer directement ?** Parce que les données brutes sont ta **source de vérité**. Si tu découvres un bug dans ta transformation 6 mois plus tard, tu peux retransformer depuis RAW. Si tu avais modifié RAW, les données originales seraient perdues.

---

## 2. Snowflake

### L'architecture en 3 couches

```
┌──────────────────────────────────────────────────┐
│                CLOUD SERVICES                     │
│   Authentification, optimisation, métadonnées     │
│   (le "cerveau" — tu n'interagis pas avec)        │
├──────────────────────────────────────────────────┤
│                COMPUTE (Warehouses)                │
│   Clusters de machines virtuelles éphémères       │
│   Allumés à la demande, minimum 60s par activation │
│   Plusieurs warehouses indépendants possibles      │
├──────────────────────────────────────────────────┤
│                STORAGE                             │
│   Données stockées en format colonnaire compressé  │
│   Sur S3/Azure Blob/GCS selon le cloud provider    │
│   Toujours disponible, même sans warehouse         │
└──────────────────────────────────────────────────┘
```

### Le Storage en détail

Snowflake stocke les données dans un format propriétaire appelé **micro-partitions** :
- Chaque table est découpée en blocs de 50-500 MB avant compression (~16 MB après compression)
- Chaque bloc est **compressé** et stocké en **colonnes** (columnar storage)
- Le stockage columnar est crucial : quand tu fais `SELECT AVG(fare_amount)`, Snowflake ne lit QUE la colonne `fare_amount`, pas les 20 autres colonnes de la table

**Pourquoi le columnar est plus rapide pour l'analytique :**
```
Stockage en lignes (OLTP) — pour lire fare_amount, tu lis tout :
[id=1, vendor=2, pickup=..., fare=25.5, tip=5.0, ...]
[id=2, vendor=1, pickup=..., fare=12.0, tip=2.0, ...]

Stockage en colonnes (OLAP) — tu lis juste ce dont tu as besoin :
fare_amount: [25.5, 12.0, 18.3, 42.1, ...]  ← seul bloc lu
tip_amount:  [5.0, 2.0, 3.5, 8.0, ...]       ← ignoré
```

Le **pruning** : Snowflake garde des métadonnées sur chaque micro-partition (min, max, count par colonne). Quand tu filtres `WHERE pickup_datetime > '2025-01-01'`, il élimine directement les partitions qui ne contiennent que des dates antérieures — sans même les lire.

### Le Compute (Warehouses) en détail

Un warehouse est un **cluster de machines virtuelles** :

| Taille | Serveurs | Crédit/heure | Cas d'usage |
|--------|----------|-------------|-------------|
| X-Small | 1 | 1 ($2-4) | Requêtes simples, dev |
| Small | 2 | 2 | Requêtes moyennes |
| Medium | 4 | 4 | Transformations dbt |
| Large | 8 | 8 | Gros volumes |
| X-Large | 16 | 16 | Chargements massifs |
| 2XL-6XL | 32-512 | 32-512 | Cas extrêmes |

> Les prix par crédit varient selon l'édition (Standard, Enterprise, Business Critical) et la région. Consulter la page pricing officielle pour les tarifs à jour.

**Facturation** : minimum **60 secondes** à chaque activation du warehouse, puis facturation à la seconde. Un warehouse qui s'active 100 fois par jour pour des requêtes de 2 secondes consomme 100 minutes (pas 200 secondes).

**Auto-suspend et auto-resume** :
```sql
CREATE WAREHOUSE NYC_TAXI_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60        -- s'éteint après 60s sans requête
    AUTO_RESUME = TRUE;      -- redémarre automatiquement
```

Le cycle de vie :
```
Requête arrive → AUTO_RESUME allume le warehouse (~1-2s)
               → Requête s'exécute
               → 60s sans activité
               → AUTO_SUSPEND éteint le warehouse
               → 0€ de compute
```

**Multi-cluster warehouse** (concept avancé) :
Si beaucoup d'utilisateurs requêtent en même temps, Snowflake peut automatiquement ajouter des clusters (scaling horizontal). C'est configuré avec `MIN_CLUSTER_COUNT` et `MAX_CLUSTER_COUNT`.

**Isolation** : chaque warehouse est indépendant. L'équipe data peut lancer un `dbt build` sur un MEDIUM pendant que l'équipe analytics fait des dashboards sur un X-SMALL. Aucune interférence — ils lisent les mêmes données mais avec des ressources séparées.

### Cloud Services en détail

Cette couche gère :
- **Query optimization** : le query planner analyse ta requête et choisit le plan d'exécution optimal
- **Result caching** : si tu relances la même requête et que les données n'ont pas changé, Snowflake retourne le résultat mis en cache instantanément (sans allumer le warehouse)
- **Metadata** : combien de lignes par table, types de colonnes, min/max par partition
- **Sécurité** : authentification, RBAC (Role-Based Access Control), chiffrement

### L'organisation logique

```
Account (ton compte Snowflake)
  └── Database (conteneur logique — comme un dossier racine)
        └── Schema (sous-dossier — organise par usage)
              ├── Table (données matérialisées sur disque)
              ├── View (requête sauvegardée, pas de stockage)
              ├── Stage (zone de transit pour fichiers)
              ├── File Format (comment lire un fichier)
              ├── Stream (capture les changements sur une table)
              ├── Task (tâche planifiée)
              ├── Pipe (chargement automatique continu)
              ├── Sequence (compteur auto-incrémenté)
              ├── Stored Procedure (bloc de code réutilisable)
              └── UDF (fonction custom utilisable dans SELECT)
```

### Table vs View — quand utiliser quoi

| | Table | View |
|---|---|---|
| **Données** | Stockées sur disque | Pas de stockage, requête recalculée à chaque appel |
| **Vitesse** | Rapide (données pré-calculées) | Plus lent (recalcule à chaque fois) |
| **Fraîcheur** | Données figées jusqu'au prochain refresh | Toujours à jour |
| **Coût storage** | Oui | Non |
| **Coût compute** | À la création/refresh | À chaque requête |
| **Quand l'utiliser** | Tables finales lues souvent (marts) | Transformations intermédiaires |

**Materialized View** (concept avancé) : un hybride — stockée comme une table, mais Snowflake la rafraîchit automatiquement quand les données sources changent. Coûte plus cher mais pratique.

### Le Stage — le pont entre fichiers et SQL

Un stage est une zone de transit pour les fichiers avant chargement.

**Stage interne** : les fichiers sont uploadés DANS Snowflake
```sql
CREATE STAGE nyc_taxi_stage;
-- Upload via l'UI ou la commande PUT
PUT file:///local/path/data.parquet @nyc_taxi_stage;
```

**Stage externe** : pointe vers un bucket cloud existant
```sql
CREATE STAGE nyc_taxi_s3_stage
    URL = 's3://nyc-tlc/trip data/';
```

**Le flux de chargement complet** :
```
1. Créer un File Format (comment lire le fichier)
   CREATE FILE FORMAT parquet_fmt TYPE = PARQUET;

2. Créer un Stage (où sont les fichiers)
   CREATE STAGE my_stage FILE_FORMAT = parquet_fmt;

3. Détecter le schéma automatiquement
   SELECT * FROM TABLE(INFER_SCHEMA(LOCATION => '@my_stage', ...));

4. Créer la table avec le schéma détecté
   CREATE TABLE trips USING TEMPLATE (...);

5. Charger les données
   COPY INTO trips FROM @my_stage;
```

**Ce que fait l'UI Snowflake quand tu uploades un fichier** : exactement ces 5 étapes, en arrière-plan, avec du SQL généré automatiquement.

### COPY INTO — le chargement des données

```sql
COPY INTO yellow_taxi_trips
    FROM @nyc_taxi_stage
    FILE_FORMAT = (TYPE = PARQUET)
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;
```

Options importantes :
- `MATCH_BY_COLUMN_NAME` : mappe les colonnes par nom (pas par position)
- `ON_ERROR = 'CONTINUE'` : continue si une ligne a une erreur
- `PATTERN = '.*2024.*'` : ne charge que les fichiers qui matchent

**Idempotence** : Snowflake garde un historique des fichiers chargés (14 jours). Si tu relances `COPY INTO` sur le même fichier, il est ignoré — pas de doublons.

### Le contrôle d'accès (RBAC)

Snowflake utilise un modèle de rôles hiérarchiques :
```
ACCOUNTADMIN          ← dieu, à éviter au quotidien
  └── SYSADMIN        ← crée les databases, schemas, warehouses
        └── DBT_ROLE  ← rôle custom pour dbt
  └── SECURITYADMIN   ← gère les utilisateurs et rôles
```

En production, on crée un rôle dédié pour dbt :
```sql
CREATE ROLE DBT_ROLE;
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE DBT_ROLE;
GRANT ALL ON DATABASE NYC_TAXI_DB TO ROLE DBT_ROLE;
```

Utiliser `ACCOUNTADMIN` pour dbt, c'est comme donner les clés root à un script — ça marche mais c'est dangereux.

### Time Travel et Fail-Safe

**Time Travel** : Snowflake garde l'historique de tes données (1 jour en standard, jusqu'à 90 jours en Enterprise).

```sql
-- Voir les données d'il y a 1 heure
SELECT * FROM trips AT(OFFSET => -3600);

-- Voir les données avant une requête spécifique
SELECT * FROM trips BEFORE(STATEMENT => '<query_id>');

-- Restaurer une table supprimée
UNDROP TABLE trips;
```

C'est un filet de sécurité. Si tu fais un `DELETE` par erreur, tu peux revenir en arrière.

**Fail-Safe** : 7 jours supplémentaires après le Time Travel, gérés par Snowflake (pas accessible par l'utilisateur). C'est pour la récupération en cas de catastrophe.

---

## 3. SQL sur Snowflake — spécificités

### Fonctions propres à Snowflake

**`TIMESTAMPDIFF`** — différence entre deux dates
```sql
TIMESTAMPDIFF(MINUTE, pickup_datetime, dropoff_datetime)
-- Retourne le nombre de minutes entre les deux dates
```

**`DAYOFWEEK` vs `DAYOFWEEKISO`** — jour de la semaine
```sql
-- DAYOFWEEK : comportement dépend du paramètre WEEK_START (défaut=0)
-- Avec WEEK_START=0 : 0=dimanche, 1=lundi, ..., 6=samedi
DAYOFWEEK(pickup_datetime)

-- DAYOFWEEKISO : toujours norme ISO, indépendant de WEEK_START
-- 1=lundi, 2=mardi, ..., 6=samedi, 7=dimanche
DAYOFWEEKISO(pickup_datetime)

-- RECOMMANDATION : toujours utiliser DAYOFWEEKISO pour éviter les surprises
-- DAYOFWEEK varie entre bases (MySQL: 1=dimanche, PostgreSQL: 0=dimanche)
-- DAYOFWEEKISO est fiable et portable
```

**`DIV0NULL`** — division sans erreur
```sql
DIV0NULL(distance, duration)
-- Si duration = 0, retourne NULL au lieu d'une erreur
-- Équivalent de : CASE WHEN duration = 0 THEN NULL ELSE distance/duration END
```

**`EXTRACT`** — extraire une partie d'une date
```sql
EXTRACT(HOUR FROM pickup_datetime)   -- 0-23
EXTRACT(MONTH FROM pickup_datetime)  -- 1-12
EXTRACT(DOW FROM pickup_datetime)    -- jour de la semaine
```

**`INFER_SCHEMA`** — détecter le schéma d'un fichier
```sql
SELECT *
FROM TABLE(INFER_SCHEMA(
    LOCATION => '@my_stage',
    FILE_FORMAT => 'parquet_format'
));
```

### Les window functions (fonctions de fenêtrage)

Essentielles en analytique — elles calculent sur un "groupe" sans réduire les lignes.

```sql
-- Pourcentage de chaque zone dans le total
COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS popularity_pct

-- OVER () = "sur l'ensemble de la table"
-- SUM(COUNT(*)) OVER () = total de toutes les lignes
```

Autres exemples utiles :
```sql
-- Rang de chaque zone par nombre de trajets
RANK() OVER (ORDER BY total_trips DESC) AS zone_rank

-- Moyenne mobile sur 7 jours
AVG(total_trips) OVER (ORDER BY trip_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)

-- Différence avec le jour précédent
total_trips - LAG(total_trips) OVER (ORDER BY trip_date) AS diff_vs_yesterday
```

### CTE (Common Table Expressions) — le `WITH`

```sql
WITH base AS (
    SELECT ... FROM source
    WHERE ...           -- nettoyage
),
enriched AS (
    SELECT ..., calculs
    FROM base           -- enrichissement
)
SELECT * FROM enriched
WHERE ...               -- filtre final
```

Les CTEs rendent le SQL lisible et modulaire. Chaque CTE est une étape nommée. C'est exactement ce qu'on fait dans notre staging.

**Point technique** : une CTE n'est PAS automatiquement matérialisée — elle est intégrée dans le plan d'exécution par le query planner. Cependant, Snowflake peut décider de matérialiser (spooler) une CTE en interne, surtout si elle est référencée plusieurs fois. Le comportement exact dépend du query planner — ne fais pas d'hypothèses sur le nombre d'évaluations.

---

## 4. dbt (data build tool)

### Ce que dbt est et n'est pas

**dbt EST** :
- Un framework de transformation SQL
- Un outil de test de données
- Un générateur de documentation
- Un gestionnaire de dépendances entre modèles

**dbt N'EST PAS** :
- Un outil de chargement de données (il ne fait pas l'Extract/Load)
- Une base de données (il s'appuie sur Snowflake, BigQuery, Postgres...)
- Un orchestrateur (il ne planifie pas les exécutions — pour ça il faut Airflow, GitHub Actions, etc.)

dbt ne fait que le **T** de ELT.

### Le mécanisme fondamental : compilation

dbt prend tes fichiers SQL avec du Jinja (les `{{ }}`) et les compile en SQL pur.

**Ton fichier** (`models/marts/daily_summary.sql`) :
```sql
SELECT
    DATE(pickup_datetime) AS trip_date,
    COUNT(*) AS total_trips
FROM {{ ref('int_trip_metrics') }}
GROUP BY trip_date
```

**Ce que dbt compile** (dans `target/compiled/`) :
```sql
SELECT
    DATE(pickup_datetime) AS trip_date,
    COUNT(*) AS total_trips
FROM NYC_TAXI_DB.STAGING.int_trip_metrics
GROUP BY trip_date
```

**Ce que dbt exécute** (dans `target/run/`) :
```sql
CREATE OR REPLACE TABLE NYC_TAXI_DB.FINAL.daily_summary AS (
    SELECT
        DATE(pickup_datetime) AS trip_date,
        COUNT(*) AS total_trips
    FROM NYC_TAXI_DB.STAGING.int_trip_metrics
    GROUP BY trip_date
);
```

Tu peux voir le SQL compilé dans `dbt/target/compiled/` et le SQL exécuté dans `dbt/target/run/`.

### `ref()` et `source()` — les deux fonctions clés

**`source()`** : référence une table externe (pas gérée par dbt)
```sql
FROM {{ source('raw', 'yellow_taxi_trips') }}
-- Compilé en : FROM NYC_TAXI_DB.RAW.yellow_taxi_trips
```
Défini dans `_sources.yml` :
```yaml
sources:
  - name: raw
    database: NYC_TAXI_DB
    schema: RAW
    tables:
      - name: yellow_taxi_trips
```

**`ref()`** : référence un autre modèle dbt
```sql
FROM {{ ref('stg_yellow_taxi_trips') }}
-- Compilé en : FROM NYC_TAXI_DB.STAGING.stg_yellow_taxi_trips
```

**Pourquoi ne pas écrire le nom complet directement ?**
1. Le `ref()` crée une **dépendance** — dbt sait l'ordre d'exécution
2. Le nom de la database/schema peut changer entre dev et prod — `ref()` le résout automatiquement
3. dbt construit le **DAG** grâce aux `ref()` et `source()`

### Le DAG (Directed Acyclic Graph)

Le DAG est le graphe de dépendances de tes modèles. dbt le construit automatiquement en analysant les `ref()` et `source()`.

```
source: raw.yellow_taxi_trips
    │
    ▼
staging: stg_yellow_taxi_trips     ← ref('stg_...')
    │
    ▼
intermediate: int_trip_metrics     ← ref('int_...')
    │
    ├──▶ marts: daily_summary      ← ref('int_...')
    ├──▶ marts: zone_analysis      ← ref('int_...')
    └──▶ marts: hourly_patterns    ← ref('int_...')
```

**Directed** : les flèches vont dans un sens (source → staging → marts)
**Acyclic** : pas de boucles (un modèle ne peut pas dépendre de lui-même, directement ou indirectement)

dbt utilise le DAG pour :
- Déterminer l'**ordre d'exécution** (staging avant intermediate avant marts)
- **Paralléliser** les modèles indépendants (les 3 marts s'exécutent en parallèle)
- **Bloquer** en cascade quand un test échoue (si int_trip_metrics échoue, les marts sont SKIP)

### La convention staging / intermediate / marts

Ce n'est pas une obligation technique, c'est un **pattern** de la communauté dbt :

**Staging (`stg_`)**
```
Rôle : point d'entrée unique par source
Règles :
  - Un modèle par table source
  - Nommé stg_<source>_<table>
  - Nettoyage SEULEMENT : filtres, renommages, cast de types
  - Pas de logique métier
  - Pas de jointures
  - Matérialisé en view
```

**Intermediate (`int_`)**
```
Rôle : transformations intermédiaires
Règles :
  - Nommé int_<description>
  - Enrichissements, catégorisations, jointures
  - La logique métier commence ici
  - Peut combiner plusieurs staging models
  - Matérialisé en view ou ephemeral (pas consommé directement)
  - La best practice officielle dbt recommande ephemeral (injecté comme CTE)
  - En pratique, view facilite le debug (on peut SELECT directement)
```

**Marts (noms métier)**
```
Rôle : tables finales pour la consommation
Règles :
  - Nommé par cas d'usage (daily_summary, zone_analysis)
  - Agrégations, métriques finales
  - Prêt pour le BI tool / dashboard
  - Matérialisé en table (performance de lecture)
```

**Pourquoi cette séparation ?**
- **Modularité** : chaque couche a une responsabilité claire
- **Réutilisabilité** : `int_trip_metrics` est utilisé par 3 marts — si tu le modifies, les 3 marts se mettent à jour
- **Debuggabilité** : si un KPI est faux, tu remontes : mart → intermediate → staging → source
- **Testabilité** : tu testes à chaque couche

### Les matérialisations

Dans `dbt_project.yml` :
```yaml
models:
  nyc_taxi_dbt:
    staging:
      +materialized: view      # CREATE VIEW
    intermediate:
      +materialized: view      # CREATE VIEW
    marts:
      +materialized: table     # CREATE TABLE ... AS SELECT
```

| Matérialisation | SQL généré | Quand l'utiliser |
|-----------------|-----------|-----------------|
| `view` | `CREATE VIEW AS SELECT` | Transformations intermédiaires, données toujours fraîches |
| `table` | `CREATE TABLE AS SELECT` | Tables finales, données lues souvent |
| `incremental` | `INSERT INTO ... WHERE` | Gros volumes, on n'ajoute que les nouvelles lignes |
| `ephemeral` | CTE injectée dans le modèle parent | Sous-requêtes réutilisables, pas de table/view créée |

**Le modèle incrémental** (concept avancé) :
Au lieu de tout recalculer, on n'insère que les nouvelles données :
```sql
{{ config(materialized='incremental') }}

SELECT * FROM {{ ref('stg_yellow_taxi_trips') }}

{% if is_incremental() %}
WHERE pickup_datetime > (SELECT MAX(pickup_datetime) FROM {{ this }})
{% endif %}
```
- Premier run : crée la table complète
- Runs suivants : n'insère que les lignes plus récentes que le max existant
- Crucial pour les tables de millions de lignes (sinon `dbt run` prendrait des heures)
- **Important** : quand tu modifies la structure d'un modèle incrémental (ajout/suppression de colonne), lance `dbt run --full-refresh --select mon_modele` pour recréer la table de zéro. Sans ça, l'ancien schéma persiste et tu auras un bug silencieux

### Le système de tests

**Generic tests** (dans `_schema.yml`) :

```yaml
models:
  - name: daily_summary
    columns:
      - name: trip_date
        tests:
          - not_null                    # jamais NULL
          - unique                      # jamais de doublon
          - accepted_values:            # uniquement ces valeurs
              arguments:
                values: ["a", "b"]
          - relationships:              # clé étrangère
              to: ref('autre_table')
              field: id
```

**Comment ça marche en interne** : dbt génère une requête SQL pour chaque test.

`not_null` génère :
```sql
SELECT COUNT(*) FROM daily_summary WHERE trip_date IS NULL
-- Si count > 0 → FAIL
```

`unique` génère :
```sql
SELECT trip_date, COUNT(*) FROM daily_summary
GROUP BY trip_date HAVING COUNT(*) > 1
-- Si des lignes → FAIL
```

**Singular tests** (fichiers SQL dans `tests/`) :
```sql
-- tests/assert_no_negative_fares.sql
SELECT * FROM {{ ref('stg_yellow_taxi_trips') }}
WHERE fare_amount < 0
-- 0 ligne retournée = PASS
-- 1+ lignes retournées = FAIL
```

**Severity** : tu peux configurer un test en `warn` au lieu de `error` :
```sql
{{ config(severity='warn') }}
SELECT * FROM ...
```
- `error` (défaut) : bloque le build, les modèles dépendants sont SKIP
- `warn` : affiche un warning, le build continue

**Threshold** : tu peux tolérer un nombre d'erreurs :
```yaml
tests:
  - not_null:
      config:
        error_if: ">100"    # FAIL seulement si plus de 100 NULLs
        warn_if: ">10"      # WARN entre 10 et 100
```

### La documentation dbt

**`_schema.yml`** : documente les modèles et colonnes
```yaml
models:
  - name: daily_summary
    description: "Résumé quotidien des trajets"
    columns:
      - name: trip_date
        description: "Date du jour"
```

**`_sources.yml`** : documente les sources externes
```yaml
sources:
  - name: raw
    tables:
      - name: yellow_taxi_trips
        description: "Données brutes NYC TLC"
```

**Générer et visualiser** :
```bash
dbt docs generate   # crée target/catalog.json + target/manifest.json
dbt docs serve      # ouvre un site web avec la doc + le DAG
```

Le site affiche :
- La description de chaque modèle et colonne
- Le SQL compilé
- Les tests associés
- Le DAG interactif (le graphe de lignée)
- Les métadonnées Snowflake (types, nombre de lignes)

### Le fichier `profiles.yml`

Stocké dans `~/.dbt/profiles.yml` (PAS dans le projet — contient des credentials) :

```yaml
nyc_taxi_dbt:              # doit matcher le "profile:" dans dbt_project.yml
  target: dev              # environnement par défaut
  outputs:
    dev:                   # configuration pour l'env dev
      type: snowflake
      account: NJ47473.west-europe.azure
      user: LOUISG
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      database: NYC_TAXI_DB
      warehouse: NYC_TAXI_WH
      schema: RAW          # schema par défaut (overridé par dbt_project.yml)
      threads: 4           # nombre de modèles exécutés en parallèle
    prod:                  # tu pourrais avoir un env prod avec un warehouse plus gros
      type: snowflake
      account: ...
      warehouse: NYC_TAXI_WH_LARGE
```

**`env_var()`** : lit une variable d'environnement. Comme ça, le mot de passe n'est jamais en clair dans un fichier versionné.

**`threads: 4`** : dbt exécute jusqu'à 4 modèles en parallèle. C'est pour ça que les 3 marts s'exécutent en même temps (ils sont indépendants dans le DAG).

### Le fichier `dbt_project.yml`

```yaml
name: 'nyc_taxi_dbt'       # nom du projet
version: '1.0.0'

profile: 'nyc_taxi_dbt'    # pointe vers profiles.yml

model-paths: ["models"]     # où chercher les modèles
test-paths: ["tests"]       # où chercher les singular tests
seed-paths: ["seeds"]       # où chercher les fichiers CSV à charger
macro-paths: ["macros"]     # où chercher les macros Jinja

models:
  nyc_taxi_dbt:             # configuration par dossier
    staging:
      +materialized: view
      +schema: STAGING
    intermediate:
      +materialized: view
      +schema: STAGING
    marts:
      +materialized: table
      +schema: FINAL
```

Le `+` devant `materialized` et `schema` signifie "appliquer à tous les modèles dans ce dossier et ses sous-dossiers".

### Les commandes dbt

| Commande | Ce qu'elle fait |
|----------|----------------|
| `dbt debug` | Teste la connexion à Snowflake |
| `dbt compile` | Compile le SQL sans l'exécuter (utile pour debug) |
| `dbt run` | Compile et exécute tous les modèles |
| `dbt test` | Lance tous les tests |
| `dbt build` | `run` + `test` dans l'ordre du DAG |
| `dbt docs generate` | Génère la documentation |
| `dbt docs serve` | Sert la documentation en local |
| `dbt clean` | Supprime `target/` et `dbt_packages/` |

**Sélecteurs** (pour cibler des modèles spécifiques) :
```bash
dbt run --select daily_summary          # un seul modèle
dbt run --select +daily_summary         # daily_summary + ses ancêtres
dbt run --select daily_summary+         # daily_summary + ses descendants
dbt run --select marts                  # tout le dossier marts
dbt test --select assert_no_negative_fares  # un seul test
```

### Jinja — le moteur de templates

dbt utilise Jinja2 (le même moteur de template que Flask) pour rendre le SQL dynamique.

**Variables** :
```sql
{{ ref('stg_yellow_taxi_trips') }}  -- référence un modèle
{{ source('raw', 'yellow_taxi_trips') }}  -- référence une source
{{ this }}  -- référence le modèle actuel (utile en incremental)
```

**Config** :
```sql
{{ config(materialized='table', schema='FINAL') }}
-- Override la config de dbt_project.yml pour CE modèle
```

**Logique conditionnelle** :
```sql
{% if is_incremental() %}
    WHERE date > (SELECT MAX(date) FROM {{ this }})
{% endif %}
```

**Macros** (fonctions réutilisables) :
```sql
-- macros/cents_to_dollars.sql
{% macro cents_to_dollars(column_name) %}
    {{ column_name }} / 100.0
{% endmacro %}

-- Utilisation dans un modèle
SELECT {{ cents_to_dollars('fare_amount_cents') }} AS fare_amount
```

---

## 5. Le pipeline complet

### Vue d'ensemble de notre projet

```
┌─────────────────────────────────────────────────────────────┐
│                     SNOWFLAKE                                │
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │   RAW    │    │   STAGING    │    │      FINAL        │  │
│  │          │    │              │    │                   │  │
│  │ yellow_  │───▶│ stg_yellow_  │───▶│ daily_summary    │  │
│  │ taxi_    │    │ taxi_trips   │    │ zone_analysis    │  │
│  │ trips    │    │              │    │ hourly_patterns  │  │
│  │          │    │ int_trip_    │───▶│                   │  │
│  │ (table)  │    │ metrics      │    │ (tables)         │  │
│  │          │    │ (views)      │    │                   │  │
│  └──────────┘    └──────────────┘    └───────────────────┘  │
│       ▲                 ▲                     │              │
│       │                 │                     ▼              │
│   Parquet files      dbt build          Dashboards / BI     │
└─────────────────────────────────────────────────────────────┘
```

### Ce qui se passe quand tu lances `dbt build`

```
1. dbt lit dbt_project.yml et profiles.yml
2. dbt scanne models/ pour trouver tous les .sql
3. dbt analyse les ref() et source() pour construire le DAG
4. dbt détermine l'ordre d'exécution :
   a. stg_yellow_taxi_trips (dépend de source, pas d'autre modèle)
   b. tests sur stg_yellow_taxi_trips
   c. int_trip_metrics (dépend de stg_)
   d. tests sur int_trip_metrics
   e. daily_summary, zone_analysis, hourly_patterns (en parallèle, dépendent de int_)
   f. tests sur les marts
5. Pour chaque modèle :
   a. Compile le Jinja en SQL pur
   b. Wrappe le SQL dans CREATE VIEW/TABLE AS (...)
   c. Envoie le SQL à Snowflake via le warehouse configuré
   d. Lance les tests associés
   e. Si un test FAIL → les modèles descendants sont SKIP
```

---

## 6. Bonnes pratiques et pièges classiques

### Les pièges qu'on a rencontrés dans ce projet

**1. `SELECT *` — l'anti-pattern silencieux**
```sql
-- MAL : si la source ajoute une colonne, tout hérite silencieusement
SELECT * FROM {{ source('raw', 'yellow_taxi_trips') }}

-- BIEN : on contrôle exactement ce qui sort
SELECT
    vendor_id,
    pickup_datetime,
    trip_distance,
    fare_amount
FROM {{ source('raw', 'yellow_taxi_trips') }}
```

**2. `DAYOFWEEK` — le piège des conventions**
```sql
-- Snowflake DAYOFWEEK (défaut WEEK_START=0) : 0=dimanche, 6=samedi
-- Snowflake DAYOFWEEKISO                    : 1=lundi, 7=dimanche (FIABLE)
-- MySQL                                     : 1=dimanche, 7=samedi
-- PostgreSQL                                : 0=dimanche, 6=samedi
-- SOLUTION : toujours utiliser DAYOFWEEKISO sur Snowflake
```

**3. Alias dans WHERE — ne fonctionne pas**
```sql
-- NE MARCHE PAS (l'alias n'existe pas encore dans le WHERE)
SELECT TIMESTAMPDIFF(MINUTE, a, b) AS duration
FROM table
WHERE duration >= 1

-- SOLUTION : répéter l'expression
WHERE TIMESTAMPDIFF(MINUTE, a, b) >= 1
-- OU utiliser une CTE
```

**4. ORDER BY dans un modèle dbt matérialisé en table**
```sql
-- INUTILE : Snowflake ne garantit pas l'ordre dans une table
-- L'ordre doit être dans la requête de consommation (dashboard, BI tool)
SELECT ... FROM marts GROUP BY date ORDER BY date  -- ❌ dans le modèle
SELECT ... FROM marts ORDER BY date                -- ✅ dans le dashboard
```

**5. Tests trop permissifs vs trop stricts**
```sql
-- Trop strict : bloque le build pour des cas limites
WHERE avg_speed > 120  -- des trajets courts légitimes dépassent

-- Solution : filtrer en amont (staging) plutôt que baisser le seuil du test
-- Règle : on corrige les données à la source, on ne baisse pas les standards
```

### Les bonnes pratiques dbt

1. **Un modèle staging par source** — pas de jointure dans staging
2. **Nommage cohérent** — `stg_`, `int_`, puis noms métier pour les marts
3. **Colonnes explicites** — jamais de `SELECT *`
4. **Tests à chaque couche** — not_null/unique sur les marts, accepted_values sur les catégorisations
5. **Documenter dans `_schema.yml`** — chaque colonne exposée
6. **`ref()` et `source()` partout** — jamais de noms de table en dur
7. **Matérialisation adaptée** — views pour l'intermédiaire, tables pour les marts

### Les bonnes pratiques Snowflake

1. **Auto-suspend systématique** — ne jamais laisser un warehouse allumé pour rien
2. **Rôles dédiés** — ne pas utiliser ACCOUNTADMIN pour les opérations courantes
3. **Nommage des objets en MAJUSCULES** — convention Snowflake (RAW, STAGING, FINAL)
4. **Time Travel** — vérifier la rétention configurée (1 jour par défaut)
5. **Monitorer les coûts** — dans Account → Usage

### Glossaire rapide

| Terme | Définition |
|-------|-----------|
| **Warehouse** | Cluster de compute Snowflake (pas un entrepôt de données) |
| **Micro-partition** | Bloc de 50-500MB de données compressées en colonnes |
| **Pruning** | Élimination des micro-partitions non pertinentes avant scan |
| **Columnar storage** | Stockage par colonne (vs par ligne) — optimisé pour l'analytique |
| **DAG** | Graphe orienté acyclique — l'ordre d'exécution des modèles dbt |
| **Matérialisation** | Comment dbt persiste un modèle (view, table, incremental) |
| **Generic test** | Test déclaratif dans _schema.yml (not_null, unique...) |
| **Singular test** | Test SQL custom dans tests/ — retourne les lignes problématiques |
| **Jinja** | Moteur de template utilisé par dbt pour rendre le SQL dynamique |
| **ref()** | Fonction dbt qui crée une dépendance entre modèles |
| **source()** | Fonction dbt qui référence une table externe |
| **CTE** | Common Table Expression — le WITH en SQL |
| **ELT** | Extract-Load-Transform — charger brut, transformer ensuite |
| **RBAC** | Role-Based Access Control — gestion des permissions par rôles |

---

## 7. Concepts avancés (pour aller plus loin)

### `dbt seed` — charger des fichiers CSV de référence

Les seeds sont des fichiers CSV versionnés dans `seeds/` qui sont chargés comme tables dans le warehouse.

Cas d'usage typique : les tables de référence qui ne viennent pas d'une API.

```csv
-- seeds/taxi_zones.csv
location_id,borough,zone,service_zone
1,EWR,Newark Airport,EWR
2,Queens,Jamaica Bay,Boro Zone
3,Bronx,Allerton/Pelham Gardens,Boro Zone
```

```bash
dbt seed  # charge tous les CSV dans le warehouse
```

Tu peux ensuite les référencer avec `{{ ref('taxi_zones') }}` dans tes modèles — par exemple pour joindre les noms de zones au `zone_analysis`.

### Packages dbt — réutiliser des macros de la communauté

dbt a un écosystème de packages. Le plus utilisé est `dbt_utils`.

```yaml
-- packages.yml (à la racine du projet dbt)
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
```

```bash
dbt deps  # installe les packages
```

Macros utiles de `dbt_utils` :
```sql
-- Générer une clé de surrogate (hash de plusieurs colonnes)
{{ dbt_utils.generate_surrogate_key(['vendor_id', 'pickup_datetime']) }}

-- Tester qu'une expression est vraie pour toutes les lignes
-- dans _schema.yml :
tests:
  - dbt_utils.expression_is_true:
      expression: "total_amount >= fare_amount"
```

### Source freshness — surveiller la fraîcheur des données

Dans `_sources.yml`, tu peux configurer dbt pour vérifier que les données sources sont récentes :

```yaml
sources:
  - name: raw
    tables:
      - name: yellow_taxi_trips
        loaded_at_field: pickup_datetime
        freshness:
          warn_after: {count: 48, period: hour}
          error_after: {count: 96, period: hour}
```

```bash
dbt source freshness  # vérifie que les données ne sont pas trop vieilles
```

Si la dernière `pickup_datetime` a plus de 48h, dbt émet un warning. Plus de 96h, une erreur. Essentiel en production pour détecter un pipeline de chargement cassé.

### `dbt build` en détail — la différence cruciale avec `dbt run` + `dbt test`

```
dbt build :  staging → test staging → intermediate → test intermediate → marts → test marts
             (interleaved : tests entre chaque couche)

dbt run && dbt test :  staging → intermediate → marts → TOUS les tests
                       (séquentiel : tous les modèles d'abord, tests ensuite)
```

La différence est cruciale : avec `dbt build`, si un test échoue sur le staging, les couches suivantes ne sont **jamais construites**. Avec `dbt run && dbt test`, les marts sont construits avec des données potentiellement corrompues, et les tests échouent après coup.

### Dynamic Tables Snowflake (concept avancé)

Depuis 2024, Snowflake propose les **Dynamic Tables** : des tables qui se rafraîchissent automatiquement quand les données sources changent, sans avoir besoin d'un orchestrateur.

```sql
CREATE DYNAMIC TABLE daily_summary
    TARGET_LAG = '1 hour'   -- rafraîchir max 1h après un changement source
    WAREHOUSE = NYC_TAXI_WH
    AS
    SELECT DATE(pickup_datetime) AS trip_date, COUNT(*) AS total_trips
    FROM staging.clean_trips
    GROUP BY trip_date;
```

dbt supporte cette matérialisation via `materialized='dynamic_table'`. C'est une alternative aux pipelines Stream + Task pour le traitement incrémental.
