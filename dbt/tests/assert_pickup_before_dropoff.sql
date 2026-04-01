-- Vérifie que la date de départ est toujours avant la date d'arrivée.
-- Protège contre des inversions de dates dans les données sources.
SELECT *
FROM {{ ref('stg_yellow_taxi_trips') }}
WHERE pickup_datetime >= dropoff_datetime
