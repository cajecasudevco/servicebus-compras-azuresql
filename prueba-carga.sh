#!/usr/bin/env bash
set -euo pipefail

API_URL="http://localhost:5081/addcompra"

echo "==> Enviando 50 compras de hombres..."
for i in {1..50}; do
  monto=$(( (RANDOM % 9000) + 1000 )) # entre 1000 y 9999
  fecha=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  payload=$(jq -n \
    --arg n "ClienteHombre$i" \
    --arg g "hombre" \
    --argjson m "$monto" \
    --arg f "$fecha" \
    '{Nombre:$n, Genero:$g, Monto:$m, Fecha:$f}')
  curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null
done
echo "==> Hombres listos."

echo "==> Enviando 50 compras de mujeres..."
for i in {1..50}; do
  monto=$(( (RANDOM % 9000) + 1000 ))
  fecha=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  payload=$(jq -n \
    --arg n "ClienteMujer$i" \
    --arg g "mujer" \
    --argjson m "$monto" \
    --arg f "$fecha" \
    '{Nombre:$n, Genero:$g, Monto:$m, Fecha:$f}')
  curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null
done
echo "==> Mujeres listas."

echo "==> Carga de prueba terminada."