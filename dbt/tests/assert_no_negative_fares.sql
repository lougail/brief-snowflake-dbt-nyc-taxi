-- Vérifie qu'aucun trajet nettoyé n'a un tarif négatif.
-- Le staging filtre déjà fare_amount >= 0, ce test le confirme.
-- Si ce test échoue, le filtre staging est cassé.
SELECT *
FROM {{ ref('stg_yellow_taxi_trips') }}
WHERE fare_amount < 0
   OR total_amount < 0
