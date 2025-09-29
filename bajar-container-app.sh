#!/usr/bin/env bash
set -euo pipefail

RG="dockercurso"
APPS=("addcompra-aca" "procesacompra-aca")

echo "==> Eliminando Container Apps en RG: $RG"
for app in "${APPS[@]}"; do
  if az containerapp show -g "$RG" -n "$app" >/dev/null 2>&1; then
    echo "Borrando $app ..."
    az containerapp delete -g "$RG" -n "$app" --yes
  else
    echo "⚠️  $app no existe (nada que borrar)"
  fi
done

echo "✅ Todos los Container Apps eliminados"