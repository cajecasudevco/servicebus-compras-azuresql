#!/usr/bin/env bash
set -euo pipefail

# URL de la API local
API_URL="http://localhost:5081/addcompra"

# Datos que cada alumno coloca
NOMBRE="${1:-AlumnoX}"   # se pasa como argumento, por defecto "AlumnoX"
GENERO="${2:-hombre}"    # hombre o mujer
MONTO="${3:-100}"        # monto en pesos

# Payload manual (sin jq, para que todos lo puedan correr)
payload="{\"Nombre\":\"$NOMBRE\",\"Genero\":\"$GENERO\",\"Monto\":$MONTO}"

echo "==> Enviando compra de $NOMBRE..."
curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d "$payload"

echo
echo "==> Compra registrada en local."