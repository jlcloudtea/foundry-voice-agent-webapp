#!/usr/bin/env bash
set -euo pipefail

required=(RG LOCATION ACR_NAME PLAN APP_NAME AI_RESOURCE FOUNDRY_RG FOUNDRY_PROJECT AGENT_NAME IMAGE_REPO IMAGE_TAG)
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

IMAGE="$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"
VOICE_ENDPOINT="https://${AI_RESOURCE}.services.ai.azure.com/"

if ! az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_REPO" --query "[?@=='$IMAGE_TAG']" -o tsv | grep -qx "$IMAGE_TAG"; then
  echo "Image not found in ACR: $IMAGE" >&2
  exit 1
fi

if ! az appservice plan show --resource-group "$RG" --name "$PLAN" >/dev/null 2>&1; then
  echo "Creating Linux App Service Plan $PLAN..."
  az appservice plan create --name "$PLAN" --resource-group "$RG" --location "$LOCATION" --is-linux --sku B1 -o none
else
  echo "App Service Plan already exists; reusing $PLAN."
fi

if ! az webapp show --resource-group "$RG" --name "$APP_NAME" >/dev/null 2>&1; then
  echo "Creating Web App $APP_NAME..."
  az webapp create --resource-group "$RG" --plan "$PLAN" --name "$APP_NAME" --deployment-container-image-name nginx:latest -o none
else
  echo "Web App already exists; reusing $APP_NAME."
fi

az webapp identity assign --resource-group "$RG" --name "$APP_NAME" -o none
PRINCIPAL_ID=$(az webapp identity show --resource-group "$RG" --name "$APP_NAME" --query principalId -o tsv)
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query id -o tsv)
FOUNDRY_ID=$(az resource show --resource-group "$FOUNDRY_RG" --name "$AI_RESOURCE" --resource-type Microsoft.CognitiveServices/accounts --query id -o tsv)

assign_role() {
  local role="$1" scope="$2"
  if az role assignment list --assignee-object-id "$PRINCIPAL_ID" --scope "$scope" --query "[?roleDefinitionName=='$role'] | length(@)" -o tsv | grep -qx '0'; then
    az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "$role" --scope "$scope" -o none
  else
    echo "Role already assigned: $role"
  fi
}

assign_role "AcrPull" "$ACR_ID"
assign_role "Cognitive Services User" "$FOUNDRY_ID"
assign_role "Foundry User" "$FOUNDRY_ID"

az webapp config set --resource-group "$RG" --name "$APP_NAME" --generic-configurations '{"acrUseManagedIdentityCreds": true}' -o none
az webapp config container set --resource-group "$RG" --name "$APP_NAME" --container-image-name "$IMAGE" --container-registry-url "https://$ACR_NAME.azurecr.io" -o none
az webapp config appsettings set --resource-group "$RG" --name "$APP_NAME" --settings \
  WEBSITES_PORT=8000 \
  AZURE_VOICELIVE_ENDPOINT="$VOICE_ENDPOINT" \
  VOICELIVE_MODE=agent \
  AZURE_VOICELIVE_AGENT_NAME="$AGENT_NAME" \
  AZURE_VOICELIVE_PROJECT="$FOUNDRY_PROJECT" -o none
az webapp config set --resource-group "$RG" --name "$APP_NAME" --web-sockets-enabled true -o none
az webapp update --resource-group "$RG" --name "$APP_NAME" --https-only true -o none
az webapp log config --resource-group "$RG" --name "$APP_NAME" --docker-container-logging filesystem -o none
az webapp restart --resource-group "$RG" --name "$APP_NAME"

HOST=$(az webapp show --resource-group "$RG" --name "$APP_NAME" --query defaultHostName -o tsv)
echo "Resumed: https://$HOST"
echo "Check logs with: az webapp log tail --resource-group \"$RG\" --name \"$APP_NAME\""
