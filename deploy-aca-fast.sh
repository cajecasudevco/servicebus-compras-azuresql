

#!/usr/bin/env bash
set -euo pipefail

# ================================
# CONFIG RÁPIDA (exporta si quieres)
# ================================
RG="${RG:-dockercurso}"
ENV_NAME="${ENV_NAME:-aca-env-compras}"      # Debe existir
LOC="${LOC:-eastus2}"                        # Solo informativo

DOCKER_USER="${DOCKER_USER:-cajecasudevco}"
IMG_ADD="${IMG_ADD:-docker.io/$DOCKER_USER/addcompra:latest}"
IMG_WKR="${IMG_WKR:-docker.io/$DOCKER_USER/procesacompra:latest}"

APP_ADD="${APP_ADD:-addcompra-aca}"
APP_WKR="${APP_WKR:-procesacompra-aca}"

# Colas
QUEUE_IN="${SERVICE_BUS_QUEUE_NAME:-compras}"
QUEUE_H="${HOMBRE_QUEUE_NAME:-hombreq}"
QUEUE_M="${MUJER_QUEUE_NAME:-mujerq}"

# Réplicas mínimas (1 para ver logs la 1ª vez)
MIN_REPLICAS_APP="${MIN_REPLICAS_APP:-1}"
MIN_REPLICAS_WKR="${MIN_REPLICAS_WKR:-1}"

# Credenciales de Docker Hub (opcionales, muy recomendadas para evitar rate limits)
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"

REV_SUFFIX="fast-$(date +%Y%m%d%H%M%S)"

# ================================
# Cargar .env si existe
# ================================
if [[ -f .env ]]; then
  echo "==> Cargando variables desde .env"
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
fi

: "${SERVICEBUS_CONNECTION_STRING:?Falta SERVICEBUS_CONNECTION_STRING (en .env o exportado)}"
: "${AZURE_SQL_CONNECTION_STRING:?Falta AZURE_SQL_CONNECTION_STRING (en .env o exportado)}"

# ================================
# Helpers
# ================================
app_exists() { az containerapp show -g "$RG" -n "$1" >/dev/null 2>&1; }

diag_or_fail() {
  local app="$1"
  local state rev
  state="$(az containerapp show -g "$RG" -n "$app" --query "properties.provisioningState" -o tsv || echo "Unknown")"
  rev="$(az containerapp show -g "$RG" -n "$app" --query "properties.latestRevisionName" -o tsv || true)"
  if [[ "$state" != "Succeeded" ]]; then
    echo "❌ $app ProvisioningState: $state"
    az containerapp show -g "$RG" -n "$app" \
      --query "{state:properties.provisioningState, error:properties.provisioningError}" -o jsonc || true
    if [[ -n "${rev:-}" ]]; then
      echo "==> Logs de SISTEMA ($rev)"
      az containerapp logs show -g "$RG" -n "$app" --revision "$rev" --type system --follow false || true
      echo "==> Logs de CONSOLA ($rev)"
      az containerapp logs show -g "$RG" -n "$app" --revision "$rev" --type console --follow false || true
    fi
    exit 1
  fi
  echo "✅ $app listo (ProvisioningState: Succeeded)"
}

# ================================
# Prechequeos
# ================================
command -v az >/dev/null || { echo "ERROR: falta Azure CLI"; exit 1; }
az containerapp env show -g "$RG" -n "$ENV_NAME" >/dev/null 2>&1 \
  || { echo "ERROR: no existe el Environment '$ENV_NAME' en RG '$RG'"; exit 1; }

echo "==> Desplegando en ACA env '$ENV_NAME' (RG: $RG, loc: $LOC)"
echo "==> Imágenes: ADD=$IMG_ADD | WKR=$IMG_WKR"

# ================================
# ADDCOMPRA (API HTTP pública en 8080)
# ================================
if ! app_exists "$APP_ADD"; then
  echo "==> Creando $APP_ADD"
  az containerapp create -g "$RG" -n "$APP_ADD" --environment "$ENV_NAME" \
    --image "$IMG_ADD" \
    --ingress external --target-port 8080 \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas "$MIN_REPLICAS_APP" --max-replicas 1 \
    --revision-suffix "$REV_SUFFIX" \
    $([[ -n "$DOCKERHUB_USER" && -n "$DOCKERHUB_TOKEN" ]] && \
      echo --registry-server docker.io --registry-username "$DOCKERHUB_USER" --registry-password "$DOCKERHUB_TOKEN") \
    --secrets sb-conn="$SERVICEBUS_CONNECTION_STRING" sql-conn="$AZURE_SQL_CONNECTION_STRING" \
    --env-vars \
      ASPNETCORE_URLS="http://+:8080" \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" >/dev/null
else
  echo "==> Actualizando $APP_ADD"
  az containerapp secret set -g "$RG" -n "$APP_ADD" --secrets \
    sb-conn="$SERVICEBUS_CONNECTION_STRING" \
    sql-conn="$AZURE_SQL_CONNECTION_STRING" >/dev/null
  # si pasas credenciales, regístralas (evita rate limit)
  if [[ -n "$DOCKERHUB_USER" && -n "$DOCKERHUB_TOKEN" ]]; then
    az containerapp registry set -g "$RG" -n "$APP_ADD" \
      --server docker.io --username "$DOCKERHUB_USER" --password "$DOCKERHUB_TOKEN" >/dev/null || true
  fi
  az containerapp update -g "$RG" -n "$APP_ADD" \
    --image "$IMG_ADD" \
    --min-replicas "$MIN_REPLICAS_APP" --max-replicas 1 \
    --revision-suffix "$REV_SUFFIX" \
    --set-env-vars \
      ASPNETCORE_URLS="http://+:8080" \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" >/dev/null
fi

diag_or_fail "$APP_ADD"
ADD_URL="https://$(az containerapp show -g "$RG" -n "$APP_ADD" --query properties.configuration.ingress.fqdn -o tsv)"
echo "==> URL AddCompra: $ADD_URL"

# ================================
# PROCESACOMPRA (Worker sin ingreso)
# ================================
if ! app_exists "$APP_WKR"; then
  echo "==> Creando $APP_WKR"
  az containerapp create -g "$RG" -n "$APP_WKR" --environment "$ENV_NAME" \
    --image "$IMG_WKR" \
    --cpu 0.25 --memory 0.5Gi \
    --min-replicas "$MIN_REPLICAS_WKR" --max-replicas 1 \
    --revision-suffix "$REV_SUFFIX" \
    $([[ -n "$DOCKERHUB_USER" && -n "$DOCKERHUB_TOKEN" ]] && \
      echo --registry-server docker.io --registry-username "$DOCKERHUB_USER" --registry-password "$DOCKERHUB_TOKEN") \
    --secrets sb-conn="$SERVICEBUS_CONNECTION_STRING" sql-conn="$AZURE_SQL_CONNECTION_STRING" \
    --env-vars \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" \
      HOMBRE_QUEUE_NAME="$QUEUE_H" \
      MUJER_QUEUE_NAME="$QUEUE_M" >/dev/null
else
  echo "==> Actualizando $APP_WKR"
  az containerapp secret set -g "$RG" -n "$APP_WKR" --secrets \
    sb-conn="$SERVICEBUS_CONNECTION_STRING" \
    sql-conn="$AZURE_SQL_CONNECTION_STRING" >/dev/null
  if [[ -n "$DOCKERHUB_USER" && -n "$DOCKERHUB_TOKEN" ]]; then
    az containerapp registry set -g "$RG" -n "$APP_WKR" \
      --server docker.io --username "$DOCKERHUB_USER" --password "$DOCKERHUB_TOKEN" >/dev/null || true
  fi
  az containerapp update -g "$RG" -n "$APP_WKR" \
    --image "$IMG_WKR" \
    --min-replicas "$MIN_REPLICAS_WKR" --max-replicas 1 \
    --revision-suffix "$REV_SUFFIX" \
    --set-env-vars \
      SERVICEBUS_CONNECTION_STRING=secretref:sb-conn \
      AZURE_SQL_CONNECTION_STRING=secretref:sql-conn \
      SERVICE_BUS_QUEUE_NAME="$QUEUE_IN" \
      HOMBRE_QUEUE_NAME="$QUEUE_H" \
      MUJER_QUEUE_NAME="$QUEUE_M" >/dev/null
fi

diag_or_fail "$APP_WKR"

# ================================
# Resumen y prueba
# ================================
echo
echo "=========== RESUMEN ==========="
echo "Env:      $ENV_NAME  (RG: $RG, $LOC)"
echo "API:      $APP_ADD   -> $ADD_URL"
echo "Worker:   $APP_WKR"
echo "Imgs:     ADD=$IMG_ADD | WKR=$IMG_WKR"
echo "==============================="
echo
echo "Prueba rápida API:"
echo "curl -X POST \"$ADD_URL/addcompra\" -H 'Content-Type: application/json' -d '{\"Nombre\":\"Carlos\",\"Genero\":\"hombre\",\"Monto\":123.45}'"
echo
echo "Logs Worker (Ctrl+C para salir):"
echo "az containerapp logs show -g $RG -n $APP_WKR --type console --follow"