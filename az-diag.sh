#!/usr/bin/env bash
set -euo pipefail

# Configura aquí el nombre de tu App Registration (displayName en Azure AD)
APP_DISPLAY_NAME="github-aca-deploy"

echo "==> Suscripción activa"
az account show --query "{name:name, id:id, tenant:tenantId}" -o table

# App Registration
echo
echo "==> App Registration"
az ad app list --display-name "$APP_DISPLAY_NAME" \
  --query "[0].{displayName:displayName, appId:appId, objectId:id}" -o table

APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Service Principal
echo
echo "==> Service Principal"
az ad sp show --id "$APP_ID" --query "{displayName:displayName, appId:appId, objectId:id}" -o table

# Ahora imprimimos exactamente lo que necesitas para GitHub Secrets
echo
echo "=========== VALORES PARA GITHUB SECRETS ==========="
echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "==================================================="
echo
echo "👉 Recuerda:"
echo "- AZURE_SQL_CONNECTION_STRING: lo sacas de tu script de SQL (connection string completa)"
echo "- SERVICEBUS_CONNECTION_STRING: lo obtienes de 'az servicebus namespace authorization-rule keys list ...'"
echo "- DOCKERHUB_USER y DOCKERHUB_TOKEN: los de tu cuenta de Docker Hub"