#!/usr/bin/env bash
set -euo pipefail

# =========================================
# CONFIG
# =========================================
RG="${RG:-dockercurso}"
ENV_NAME="${ENV_NAME:-aca-env-compras}"
LOC="${LOC:-eastus2}"

# =========================================
# Crear Container Apps Environment
# =========================================
echo "==> Creando Container Apps Environment '$ENV_NAME' en RG '$RG' ($LOC)..."

az containerapp env create \
  --name "$ENV_NAME" \
  --resource-group "$RG" \
  --location "$LOC"

# =========================================
# Resumen
# =========================================
echo
echo "=========== ACA ENV CREADO ==========="
az containerapp env show -g "$RG" -n "$ENV_NAME" -o table
echo "======================================"