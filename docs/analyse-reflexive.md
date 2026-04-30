# Analyse réflexive — Pipeline NYC Taxi (Snowflake + dbt)

## Contexte

Construction d'un Data Warehouse analytique sur Snowflake à partir du dataset
NYC Yellow Taxi (12 mois, ~47M trajets bruts, ~8 GB en Parquet), avec une
architecture en 3 couches RAW → STAGING → FINAL, industrialisation via dbt Core
et orchestration mensuelle via GitHub Actions.

## Difficultés rencontrées et solutions

### 1. Connexion dbt → Snowflake

**Problème** : `dbt debug` échouait sur l'authentification. Le `profiles.yml`
n'était pas trouvé, puis l'identifiant de compte Snowflake n'était pas au bon
format (le format attendu par dbt est `org-account`, pas l'URL complète).

**Solution** : création de `~/.dbt/profiles.yml` au bon emplacement, mise à jour
de l'identifiant de compte, validation avec `dbt debug` avant tout build.

### 2. Schéma cible des modèles dbt

**Problème** : par défaut, dbt préfixe le schéma cible avec celui défini dans
`profiles.yml` (ex : `RAW_STAGING` au lieu de `STAGING`). L'architecture
cible imposait des schémas nommés exactement `RAW`, `STAGING`, `FINAL`.

**Solution** : écriture d'une macro `generate_schema_name.sql` qui surcharge
le comportement par défaut de dbt et utilise le schéma custom tel quel,
sans préfixe.

### 3. Bug DAYOFWEEK / classification semaine vs weekend

**Problème** : `DAYOFWEEK` dans Snowflake retourne `0 = dimanche` par défaut.
Le code initial supposait `0 = lundi` et classait donc vendredi + samedi en
weekend, faussant l'analyse semaine vs weekend dans les marts.

**Solution** : remplacement par `DAYOFWEEKISO` (norme ISO : 1 = lundi,
7 = dimanche) et condition `pickup_dow IN (6, 7)` pour le weekend. Bug
détecté lors de la review et confirmé par un test custom
(`assert_daily_summary_has_data`).

### 4. Vitesses aberrantes après nettoyage

**Problème** : même après filtrage des distances et durées négatives, certains
trajets affichaient des vitesses calculées de plusieurs centaines de mph
(typiquement : trajet de 0.5 mile en 10 secondes = 180 mph), faussant les
analyses de vitesse par zone.

**Solution** : ajout de deux filtres successifs dans le staging — durée
minimum de 1 minute (`TIMESTAMPDIFF(MINUTE, pickup, dropoff) >= 1`) puis
plafond de vitesse `avg_speed_mph <= 120`. Validation par un test custom
`assert_reasonable_speed`.

### 5. Volumes de données non négligeables

**Problème** : ~8 GB de fichiers Parquet à charger, impossibles à versionner
sur Git (limite GitHub à 100 MB par fichier). Risque aussi d'engager des
crédits Snowflake importants pendant le développement.

**Solution** : ajout de `data/parquet/*.parquet` au `.gitignore`, utilisation
d'un warehouse Snowflake X-SMALL avec auto-suspend à 60 secondes pour limiter
la consommation, développement en local sur un échantillon avant le full load.

## Choix techniques et justification

### Architecture en 3 schémas (RAW / STAGING / FINAL)

Choix imposé par le brief mais cohérent avec les pratiques modernes (médaillon
bronze/silver/gold). Permet de :
- garder une trace immuable des données brutes (auditabilité, reprocessing)
- isoler la logique de nettoyage du métier
- ne livrer aux dashboards que des tables agrégées et stables

### Matérialisation : table en RAW et FINAL, vue en STAGING

- **RAW en table** : données brutes copiées une seule fois depuis le stage
  Snowflake, plus jamais retouchées.
- **STAGING en vue** : nettoyage léger, recalculé à chaque requête. Évite la
  duplication d'un volume important pour une transformation simple.
- **FINAL en table** : agrégations coûteuses, matérialisées une fois pour
  servir les dashboards rapidement (Evidence requête en quasi-temps réel).

### dbt Core plutôt que SQL pur

Le tronc commun aurait pu se faire en pur SQL via la console Snowflake. Le
choix d'industrialiser dès le départ avec dbt Core a apporté :
- versionning des transformations (chaque modification est traçable dans Git)
- tests automatisés (36 tests, schema + custom, exécutés en CI)
- documentation auto-générée (DAG visuel, lineage entre modèles)
- réutilisabilité via les refs (`{{ ref('stg_yellow_taxi_trips') }}`) qui
  garantit l'ordre d'exécution sans le coder à la main

### GitHub Actions pour l'orchestration

Choix de `cron: '0 6 1 * *'` (1er du mois à 6h UTC) qui colle au rythme de
publication mensuel des données NYC TLC. Les credentials Snowflake sont
stockés en secrets GitHub, jamais en clair dans le repo. Le `profiles.yml`
est généré à la volée pendant le job.

### Evidence pour le dashboard

Choix d'Evidence plutôt que Streamlit ou Metabase :
- code-as-config (markdown + SQL), versionnable
- déploiement statique simple
- intégration directe avec Snowflake sans serveur intermédiaire

## Compétences acquises

- **Snowflake** : provisioning d'un warehouse, gestion des rôles et schémas,
  création de stages externes, chargement de fichiers Parquet, écriture de
  SQL analytique (window functions, agrégations multi-niveaux).
- **dbt Core** : structure d'un projet (staging / intermediate / marts),
  matérialisations, tests schema (`not_null`, `unique`, `accepted_values`),
  tests custom en SQL, macros (`generate_schema_name`), génération de
  documentation et DAG.
- **Qualité des données** : identification systématique des anomalies (NULL,
  négatifs, valeurs aberrantes, incohérences temporelles), conception de
  filtres motivés et quantification du taux de rejet (~7%).
- **CI/CD** : workflows GitHub Actions, gestion sécurisée des secrets,
  génération dynamique de fichiers de config.
- **Visualisation** : Evidence (composants `BigValue`, `LineChart`, `BarChart`,
  `DataTable`), connexion à Snowflake, mise en page d'un dashboard analytique.

## Compétences à approfondir

- **Modélisation dimensionnelle** : les marts actuels sont des agrégations
  business, mais une vraie modélisation en étoile (fact_trips + dim_zone +
  dim_time + dim_payment) serait plus robuste pour des analyses ad-hoc. La
  table `fact_trips` est un premier pas dans cette direction.
- **dbt avancé** : packages (`dbt_utils`, `dbt_expectations`), snapshots pour
  le SCD Type 2, exposures pour documenter les consommateurs, sources avec
  freshness checks.
- **Optimisation Snowflake** : clustering keys, micro-partitions, query
  profiling, choix de la taille du warehouse en fonction de la charge.
- **Orchestration plus riche** : Airflow ou Dagster pour des dépendances
  complexes (chargement Parquet → dbt → tests → notification → refresh
  dashboard), au-delà du simple cron mensuel de GitHub Actions.
- **Tests de données** : tests de cohérence métier au-delà des contraintes
  techniques (ex : revenu mensuel toujours croissant, distribution des
  paiements stable d'un mois à l'autre).

## Parallèle avec un contexte professionnel

Ce projet reproduit la structure d'un pipeline analytique en production tel
qu'on le trouve dans une équipe data moderne :

- **Le découpage RAW / STAGING / FINAL** correspond exactement au pattern
  médaillon (bronze / silver / gold) utilisé chez la plupart des entreprises
  ayant adopté Snowflake, BigQuery ou Databricks.
- **dbt Core est le standard de l'industrie** pour les transformations SQL
  versionnées. Une équipe data type a un repo dbt avec dizaines de modèles,
  des centaines de tests, et un job de build qui tourne plusieurs fois par
  jour.
- **L'orchestration via GitHub Actions** est représentative pour des
  pipelines simples ; pour de la production critique on utiliserait plutôt
  Airflow, Dagster ou dbt Cloud, mais la logique reste la même : trigger
  programmé, secrets isolés, alerting en cas d'échec.
- **Le rapport qualité** (`docs/rapport-qualite-donnees.md`) joue le rôle
  d'un *data contract* documenté : chaque filtre est motivé, le taux de
  rejet est quantifié, les tests garantissent que les filtres restent
  effectifs dans le temps.
- **Le dashboard Evidence** correspond au livrable final attendu par les
  équipes métier : KPIs lisibles sans avoir à écrire de SQL.

La principale différence avec un contexte pro réel serait la volumétrie
(des milliards de lignes plutôt que des millions), l'incrémentalité (modèles
`incremental` dans dbt plutôt que `table` recalculée intégralement) et la
gouvernance (rôles fins, masking de PII, lineage formel). L'architecture et
les outils, eux, sont identiques.
