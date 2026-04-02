-- Pourboire par mode de paiement
SELECT
    payment_type,
    CASE
        WHEN payment_type = 1 THEN 'Carte'
        WHEN payment_type = 2 THEN 'Cash'
        WHEN payment_type = 3 THEN 'Gratuit'
        WHEN payment_type = 4 THEN 'Litige'
        ELSE 'Autre'
    END AS payment_label,
    COUNT(*) AS total_trips,
    AVG(tip_amount) AS avg_tip,
    AVG(tip_percentage) AS avg_tip_pct,
    SUM(tip_amount) AS total_tips
FROM {{ ref('int_trip_metrics') }}
GROUP BY payment_type
