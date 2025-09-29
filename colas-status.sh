#!/usr/bin/env bash
set -euo pipefail

RG="dockercurso"
NAMESPACE="dockerleo"

echo "==> Estado simplificado de las colas en $NAMESPACE"

for q in compras hombreq mujerq; do
  az servicebus queue show \
    -g "$RG" \
    --namespace-name "$NAMESPACE" \
    --name "$q" \
    --query "{Cola:name, Mensajes:messageCount, Estado:status, Region:location, TTL:defaultMessageTimeToLive, MaxReintentos:maxDeliveryCount}" \
    -o table
done