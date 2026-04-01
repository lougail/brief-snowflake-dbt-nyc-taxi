-- Vérifie que le résumé quotidien ne contient pas de jours sans trajets
-- ou avec des revenus négatifs (ce qui indiquerait un problème d'agrégation).
SELECT *
FROM {{ ref('daily_summary') }}
WHERE total_trips <= 0
   OR total_revenue < 0
