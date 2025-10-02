#!/usr/bin/env bash
set -euo pipefail

APP_DISPLAY_NAME="github-aca-deploy"   # tu App Registration

echo "== Suscripción activa =="
az account show --query "{name:name,id:id,tenant:tenantId}" -o table

APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo
echo "== App registration & Service Principal =="
az ad app show --id "$APP_ID" --query "{displayName:displayName,appId:appId,objectId:id}" -o table
az ad sp show --id "$APP_ID"  --query "{displayName:displayName,appId:appId,objectId:id}" -o table || true

echo
echo "=========== Secrets para GitHub ==========="
echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "SERVICEBUS_CONNECTION_STRING=$(az servicebus namespace authorization-rule keys list \
  --resource-group dockercurso \
  --namespace-name dockerleo \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv)"
echo "AZURE_SQL_CONNECTION_STRING=Server=tcp:compras-sql-leodockercurso.database.windows.net,1433;Database=comprasdb;User ID=sqladminuser;Password=P@ssw0rd8321;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
echo "=========================================="