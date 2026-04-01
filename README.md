# NYC Taxi Data Pipeline — Snowflake + dbt

Pipeline de données des taxis jaunes de New York (NYC TLC) avec Snowflake comme data warehouse et dbt pour les transformations.

## Architecture

```
Fichiers Parquet (NYC TLC)
        │
        ▼
┌─────────────────────────────┐
│  Snowflake - NYC_TAXI_DB    │
│                             │
│  RAW ──► STAGING ──► FINAL  │
│  (brut)   (nettoyé)  (KPI) │
└─────────────────────────────┘
        │
        ▼
   Dashboards / Analyse
```

### Couches de données

| Couche | Contenu | Matérialisation |
|--------|---------|-----------------|
| **RAW** | Données brutes des fichiers parquet, chargées telles quelles | Table |
| **STAGING** | Données nettoyées et enrichies (durée, vitesse, catégories business) | View |
| **FINAL** | Tables analytiques agrégées (résumé quotidien, zones, patterns horaires) | Table |

## Structure du projet

```
.
├── sql/
│   ├── 01_setup.sql          # Création warehouse, database, schemas
│   ├── 02_load_data.sql       # Chargement des fichiers parquet → RAW
│   ├── 03_staging.sql         # Nettoyage et enrichissement → STAGING
│   └── 04_final.sql           # Tables analytiques → FINAL
├── dbt/
│   ├── models/
│   │   ├── staging/           # stg_yellow_taxi_trips (nettoyage)
│   │   ├── intermediate/      # int_trip_metrics (catégories business)
│   │   └── marts/             # daily_summary, zone_analysis, hourly_patterns
│   └── tests/                 # Tests custom (singular tests)
├── docs/
│   └── snowflake-architecture.md  # Documentation Snowflake détaillée
└── data/                      # Fichiers parquet (non versionnés)
```

## Prérequis

- Un compte Snowflake (trial 30 jours avec $400 de crédits)
- Python 3.9+
- dbt-core + dbt-snowflake

## Installation

### 1. Snowflake

Exécuter les scripts SQL dans l'ordre dans la console Snowflake :

```sql
-- 1. Infrastructure
-- Exécuter sql/01_setup.sql

-- 2. Chargement des données
-- Exécuter sql/02_load_data.sql
```

### 2. dbt

```bash
# Installer dbt
pip install dbt-core dbt-snowflake

# Configurer la connexion Snowflake
# Éditer ~/.dbt/profiles.yml :
```

```yaml
nyc_taxi_dbt:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <ton-account>       # ex: ab12345.eu-west-1
      user: <ton-user>
      password: <ton-password>
      role: DBT_ROLE           # éviter ACCOUNTADMIN en production
      database: NYC_TAXI_DB
      warehouse: NYC_TAXI_WH
      schema: RAW
      threads: 4
```

```bash
# Vérifier la connexion
cd dbt
dbt debug

# Lancer le pipeline complet (modèles + tests)
dbt build

# Générer la documentation et le DAG
dbt docs generate
dbt docs serve
```

## Modèles dbt

### Staging : `stg_yellow_taxi_trips`
Nettoyage des données brutes avec les filtres qualité :
- Tarifs positifs (`fare_amount >= 0`)
- Distances cohérentes (entre 0.1 et 100 miles)
- Zones de départ/arrivée non nulles
- Date de départ avant date d'arrivée

Enrichissements : durée du trajet, heure/jour/mois, vitesse moyenne, % de pourboire.

### Intermediate : `int_trip_metrics`
Ajout de catégories business :
- **Distance** : court (≤1mi), moyen (1-5mi), long (5-10mi), très long (>10mi)
- **Période** : rush matinal (6-9h), journée (10-15h), rush soir (16-19h), soirée (20-23h), nuit (0-5h)
- **Type de jour** : semaine vs weekend

### Marts
- **`daily_summary`** — Volume, distance, revenu et durée moyens par jour
- **`zone_analysis`** — Popularité et revenu par zone de départ
- **`hourly_patterns`** — Demande et revenu par heure de la journée

## Tests

### Tests schema (dans `_schema.yml`)
- `not_null` et `unique` sur les clés des marts
- `accepted_values` sur les catégories business (distance, période, type de jour)

### Tests custom (dans `tests/`)
- `assert_no_negative_fares` — Aucun tarif négatif après nettoyage
- `assert_valid_trip_distances` — Distances dans les bornes [0.1, 100]
- `assert_pickup_before_dropoff` — Départ toujours avant arrivée
- `assert_reasonable_speed` — Pas de vitesse > 120 mph
- `assert_daily_summary_has_data` — Pas de jour vide ou revenu négatif

```bash
# Lancer uniquement les tests
dbt test

# Lancer un test spécifique
dbt test --select assert_no_negative_fares
```

## KPIs disponibles

À partir des tables FINAL :
- Volume mensuel de trajets
- Revenu moyen par trajet
- Distance moyenne parcourue
- Zones les plus actives
- Patterns de demande par heure
- Comparaison semaine vs weekend
