#!/usr/bin/env bash
set -euo pipefail

required=(RG PLAN APP_NAME)
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

echo "Pause strategy"
echo "  Delete Web App:       $APP_NAME"
echo "  Delete App Service:   $PLAN"
echo "  Preserve resource group: $RG"
echo "  Preserve ACR and its Docker images"
echo "  Preserve the separate Microsoft Foundry resource and agent"
echo
echo "Important: stopping a Web App alone does not remove App Service Plan charges."
read -r -p "Type PAUSE to continue: " answer
[[ "$answer" == "PAUSE" ]] || { echo "Cancelled."; exit 0; }

if az webapp show --resource-group "$RG" --name "$APP_NAME" >/dev/null 2>&1; then
  echo "Deleting Web App $APP_NAME..."
  az webapp delete --resource-group "$RG" --name "$APP_NAME"
else
  echo "Web App $APP_NAME does not exist; skipping."
fi

if az appservice plan show --resource-group "$RG" --name "$PLAN" >/dev/null 2>&1; then
  echo "Deleting App Service Plan $PLAN..."
  az appservice plan delete --resource-group "$RG" --name "$PLAN" --yes
else
  echo "App Service Plan $PLAN does not exist; skipping."
fi

echo "Paused. ACR and Foundry resources were not deleted."
echo "Run scripts/resume.sh with the required variables to recreate hosting."
