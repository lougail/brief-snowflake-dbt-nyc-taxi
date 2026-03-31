-- Override du comportement par défaut de dbt
-- Utilise le nom de schéma tel quel (STAGING, FINAL) sans préfixe
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
