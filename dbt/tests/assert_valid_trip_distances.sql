-- Vérifie que toutes les distances sont dans les bornes [0.1, 100] miles.
-- Le staging filtre BETWEEN 0.1 AND 100, ce test le confirme.
SELECT *
FROM {{ ref('stg_yellow_taxi_trips') }}
WHERE trip_distance < 0.1
   OR trip_distance > 100
