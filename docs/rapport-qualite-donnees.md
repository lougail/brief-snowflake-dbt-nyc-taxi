# Rapport qualité des données — NYC Yellow Taxi

## Source des données

- **Origine** : NYC Taxi & Limousine Commission (TLC)
- **Format** : Fichiers Parquet mensuels
- **Période** : 2024-2025
- **Volume brut** : ~47 millions de trajets

## Problèmes identifiés dans les données brutes

### 1. Montants négatifs (~4.15%)

**Problème** : des valeurs de `fare_amount` et `total_amount` négatives,
correspondant à des ajustements ou remboursements.

**Impact** : fausse les calculs de revenu moyen et total.

**Correction** : filtre `fare_amount >= 0 AND total_amount >= 0` dans le staging.

### 2. Distances aberrantes (~2.62%)

**Problème** : des trajets avec une distance de 0 mile (véhicule
n'a pas bougé) ou supérieure à 100 miles (incohérent pour NYC).

**Impact** : fausse les moyennes de distance et de vitesse.

**Correction** : filtre `trip_distance BETWEEN 0.1 AND 100` dans le staging.

### 3. Dates incohérentes

**Problème** : certains trajets ont une date de dépose antérieure
à la date de prise en charge (`dropoff < pickup`).

**Impact** : produit des durées négatives, fausse les calculs de vitesse.

**Correction** : filtre `pickup_datetime < dropoff_datetime` dans le staging.

### 4. Zones de localisation manquantes

**Problème** : des trajets sans zone de départ ou d'arrivée
(`pu_location_id` ou `do_location_id` NULL).

**Impact** : impossible de faire l'analyse par zone sur ces trajets.

**Correction** : filtre `pu_location_id IS NOT NULL AND do_location_id IS NOT NULL`.

### 5. Trajets trop courts (< 1 minute)

**Problème** : des trajets d'une durée inférieure à 1 minute qui produisent
des vitesses calculées aberrantes (ex : 0.5 mile en 10 secondes = 180 mph).

**Impact** : fausse les moyennes de vitesse et de durée.

**Correction** : filtre `TIMESTAMPDIFF(MINUTE, pickup, dropoff) >= 1` dans le staging.

### 6. Vitesses aberrantes (> 120 mph)

**Problème** : même après le filtre de durée minimum, certains trajets
ont des vitesses calculées supérieures à 120 mph, physiquement
impossibles pour un taxi à NYC.

**Impact** : fausse les analyses de vitesse par zone et par période.

**Correction** : filtre `avg_speed_mph <= 120` dans le staging.

## Résumé des filtres appliqués

| Filtre | Condition | Lignes exclues (estimé) |
|--------|-----------|------------------------|
| Montants négatifs | `fare_amount >= 0 AND total_amount >= 0` | ~4.15% |
| Distances aberrantes | `trip_distance BETWEEN 0.1 AND 100` | ~2.62% |
| Dates incohérentes | `pickup_datetime < dropoff_datetime` | < 0.5% |
| Zones manquantes | `pu_location_id IS NOT NULL AND do_location_id IS NOT NULL` | < 1% |
| Durée trop courte | `TIMESTAMPDIFF(MINUTE, ...) >= 1` | ~1% |
| Vitesse aberrante | `avg_speed_mph <= 120` | ~0.5% |

**Volume après nettoyage** : ~43.8 millions de trajets (sur ~47M bruts), soit ~93% conservés.

## Tests de validation

### Tests schema (dans `_schema.yml`)

31 tests automatiques vérifiant :
- `not_null` sur les colonnes clés (dates, montants, zones, distances)
- `unique` sur les clés naturelles des marts (trip_date, zone_id, pickup_hour)
- `accepted_values` sur les catégories (distance_category, time_period, day_type)

### Tests custom (dans `tests/`)

| Test | Ce qu'il vérifie |
|------|-----------------|
| `assert_no_negative_fares` | Aucun tarif négatif après nettoyage |
| `assert_valid_trip_distances` | Distances entre 0.1 et 100 miles |
| `assert_pickup_before_dropoff` | Départ toujours avant arrivée |
| `assert_reasonable_speed` | Pas de vitesse > 120 mph |
| `assert_daily_summary_has_data` | Pas de jour vide ou revenu négatif |

### Résultat

```
dbt build : PASS=36 WARN=0 ERROR=0 SKIP=0
```

Tous les tests passent — les filtres de nettoyage fonctionnent correctement.

## Bug corrigé : DAYOFWEEK

Lors de la review, un bug a été détecté sur la classification semaine/weekend.

**Problème** : `DAYOFWEEK` dans Snowflake retourne 0=dimanche par défaut
(pas 0=lundi comme supposé). Le code classait vendredi+samedi en weekend
au lieu de samedi+dimanche.

**Correction** : remplacement par `DAYOFWEEKISO` (norme ISO : 1=lundi, 7=dimanche)
et condition `pickup_dow IN (6, 7)` pour le weekend.
