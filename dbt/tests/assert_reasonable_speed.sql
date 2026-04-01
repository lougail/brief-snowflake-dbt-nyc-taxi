-- Vérifie qu'aucun trajet n'a une vitesse aberrante (> 120 mph).
-- Un taxi à NYC ne devrait jamais dépasser cette vitesse.
-- Les trajets < 1 minute sont déjà filtrés dans le staging
-- pour éviter les divisions par des durées quasi-nulles.
SELECT *
FROM {{ ref('int_trip_metrics') }}
WHERE avg_speed_mph > 120
  AND avg_speed_mph IS NOT NULL
