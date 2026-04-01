---
title: NYC Taxi Dashboard
---

# NYC Yellow Taxi — KPIs

Dashboard des trajets de taxi jaune à New York, alimenté par les tables analytiques dbt sur Snowflake.

```sql kpi_summary
SELECT
    COUNT(*) AS total_days,
    SUM(total_trips) AS total_trips,
    ROUND(AVG(avg_revenue), 2) AS avg_revenue_per_trip,
    ROUND(AVG(avg_distance), 2) AS avg_distance_miles,
    ROUND(SUM(total_revenue), 0) AS total_revenue
FROM nyc_taxi.daily_summary
```

<BigValue
    data={kpi_summary}
    value=total_trips
    title="Trajets totaux"
    fmt=num0
/>

<BigValue
    data={kpi_summary}
    value=avg_revenue_per_trip
    title="Revenu moyen / trajet"
    fmt=usd
/>

<BigValue
    data={kpi_summary}
    value=avg_distance_miles
    title="Distance moyenne (miles)"
    fmt=num2
/>

<BigValue
    data={kpi_summary}
    value=total_revenue
    title="Revenu total"
    fmt=usd0
/>

## Volume quotidien de trajets

```sql daily
SELECT * FROM nyc_taxi.daily_summary
```

<LineChart
    data={daily}
    x=trip_date
    y=total_trips
    title="Nombre de trajets par jour"
/>

<LineChart
    data={daily}
    x=trip_date
    y=total_revenue
    title="Revenu total par jour ($)"
    yFmt=usd0
/>

## Patterns horaires

```sql hourly
SELECT * FROM nyc_taxi.hourly_patterns
```

<BarChart
    data={hourly}
    x=pickup_hour
    y=total_trips
    title="Demande par heure de la journée"
    xAxisTitle="Heure"
    yAxisTitle="Nombre de trajets"
/>

<BarChart
    data={hourly}
    x=pickup_hour
    y=avg_revenue
    title="Revenu moyen par heure ($)"
    xAxisTitle="Heure"
    yAxisTitle="Revenu moyen ($)"
    yFmt=usd
/>

## Top 20 zones de départ

```sql zones
SELECT 'Zone ' || CAST(zone_id AS INT) AS zone, total_trips, popularity_pct, avg_revenue, total_revenue
FROM nyc_taxi.zone_analysis LIMIT 20
```

<BarChart
    data={zones}
    x=zone
    y=total_trips
    title="Top 20 zones par nombre de trajets"
    swapXY=true
/>

<DataTable
    data={zones}
    rows=20
>
    <Column id=zone title="Zone" />
    <Column id=total_trips title="Trajets" fmt=num0 />
    <Column id=popularity_pct title="Part (%)" />
    <Column id=avg_revenue title="Rev. moyen ($)" fmt=usd />
    <Column id=total_revenue title="Rev. total ($)" fmt=usd0 />
</DataTable>
