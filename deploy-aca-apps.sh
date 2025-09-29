#!/usr/bin/env bash
set -euo pipefail

# =========================================
# CONFIG REQUERIDA (ajusta o exporta antes)
# =========================================
RG="${RG:-dockercurso}"
ENV_NAME="${ENV_NAME:-aca-env-compras}"   # Debe existir
LOC="${LOC:-eastus2}"                      # Solo informativo

# Imágenes (Docker Hub públicas por simplicidad)
DOCKER_USER="${DOCKER_USER:-cajecasudevco}"
IMG_ADD="${IMG_ADD:-docker.io/$DOCKER_USER/addcompra:latest}"
IMG_WKR="${IMG_WKR:-docker.io/$DOCKER_USER/procesacompra:latest}"

# Nombres de las apps
APP_ADD="${APP_ADD:-addcompra-aca}"
APP_WKR="${APP_WKR:-procesacompra-aca}"

# Colas (Service Bus Basic)
QUEUE_IN="${SERVICE_BUS_QUEUE_NAME:-compras}"
QUEUE_H="${HOMBRE_QUEUE_NAME:-hombreq}"
QUEUE_M="${MUJER_QUEUE_NAME:-mujerq}"

# ============================
# Cargar .env si existe
# ============================
if [ -f .env ]; then
  echo "==> Cargando variables desde .env"
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
fi

: "${SERVICEBUS_CONNECTION_STRING:?Falta SERVICEBUS_CONNECTION_STRING (en .env o exportado)}"
: "${AZURE_SQL_CONNECTION_STRING:?Falta AZURE_SQL_CONNECTION_STRING (en .env o exportado)}"

# ============================
# Prechequeos
# ============================
command -v az >/dev/null 2>&1 || { echo "ERROR: falta Azure CLI"; exit 1; }
az containerapp env show -g "$RG" -n "$ENV_NAME" >/dev/null 2>&1 \
  || { echo "ERROR: no existe el Environment '$ENV_NAME' en RG '$RG'"; exit 1; }

echo "==> Desplegando en ACA env '$ENV_NAME' (RG: $RG, loc: $LOC)"

# =========================================
# ADDCOMPRA (API HTTP pública)
# =========================================
if ! az containerapp show -g "$RG" -n "$APP_ADD" >/dev/null 2>&1; then
  echo "==> Creando $APP_ADD (con secrets en create)"
  az containerapp create -g "$RG" -n "$APP_ADD" --environment "$ENV_NAME" \
    --image "$IMG_ADD" \
    --ingress external --target-port 8080 \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas 0 --max-replicas 1 \
    --secrets sb-conn="$SERVICEBUS_CONNECTION_STRING" sql-conn="$AZURE_SQL_CONNECTION_STRING" \
    --env-vars \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" >/dev/null
else
  echo "==> Actualizando $APP_ADD (secrets + env vars)"
  az containerapp secret set -g "$RG" -n "$APP_ADD" --secrets \
    sb-conn="$SERVICEBUS_CONNECTION_STRING" \
    sql-conn="$AZURE_SQL_CONNECTION_STRING" >/dev/null
  az containerapp update -g "$RG" -n "$APP_ADD" \
    --image "$IMG_ADD" \
    --set-env-vars \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" >/dev/null
fi

ADD_URL="https://$(az containerapp show -g $RG -n $APP_ADD --query properties.configuration.ingress.fqdn -o tsv)"
echo "==> URL pública de AddCompra: $ADD_URL"

# =========================================
# PROCESACOMPRA (Worker sin ingreso)
# =========================================
if ! az containerapp show -g "$RG" -n "$APP_WKR" >/dev/null 2>&1; then
  echo "==> Creando $APP_WKR (con secrets en create)"
  az containerapp create -g "$RG" -n "$APP_WKR" --environment "$ENV_NAME" \
    --image "$IMG_WKR" \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas 0 --max-replicas 1 \
    --secrets sb-conn="$SERVICEBUS_CONNECTION_STRING" sql-conn="$AZURE_SQL_CONNECTION_STRING" \
    --env-vars \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" \
      HOMBRE_QUEUE_NAME="$QUEUE_H" \
      MUJER_QUEUE_NAME="$QUEUE_M" >/dev/null
else
  echo "==> Actualizando $APP_WKR (secrets + env vars)"
  az containerapp secret set -g "$RG" -n "$APP_WKR" --secrets \
    sb-conn="$SERVICEBUS_CONNECTION_STRING" \
    sql-conn="$AZURE_SQL_CONNECTION_STRING" >/dev/null
  az containerapp update -g "$RG" -n "$APP_WKR" \
    --image "$IMG_WKR" \
    --set-env-vars \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" \
      HOMBRE_QUEUE_NAME="$QUEUE_H" \
      MUJER_QUEUE_NAME="$QUEUE_M" >/dev/null
fi

# ============================
# Resumen y pruebas
# ============================
echo
echo "=========== RESUMEN ==========="
echo "Environment:  $ENV_NAME"
echo "App API:      $APP_ADD"
echo "App Worker:   $APP_WKR"
echo "API URL:      $ADD_URL"
echo "==============================="
echo
echo "Prueba rápida:"
echo "curl -X POST \"$ADD_URL/addcompra\" -H \"Content-Type: application/json\" -d '{\"Nombre\":\"Carlos\",\"Genero\":\"hombre\",\"Monto\":123.45}'"
echo
echo "Logs del worker (Ctrl+C para salir):"
echo "az containerapp logs show -g $RG -n $APP_WKR --follow"