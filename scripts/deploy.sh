#!/usr/bin/env bash
set -euo pipefail

required=(RG LOCATION ACR_NAME PLAN APP_NAME AI_RESOURCE FOUNDRY_RG FOUNDRY_PROJECT AGENT_NAME)
for var in "${required[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

IMAGE_REPO="${IMAGE_REPO:-voicelive-web}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
VOICE_ENDPOINT="https://${AI_RESOURCE}.services.ai.azure.com/"
IMAGE="$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"

echo "Creating resource group and registry..."
az group create --name "$RG" --location "$LOCATION" -o none
az acr create --resource-group "$RG" --name "$ACR_NAME" --sku Basic -o none

echo "Building and pushing container..."
docker build -f Dockerfile.python -t "$IMAGE" .
az acr login --name "$ACR_NAME"
docker push "$IMAGE"

echo "Creating App Service infrastructure..."
az appservice plan create --name "$PLAN" --resource-group "$RG" --location "$LOCATION" --is-linux --sku B1 -o none
az webapp create --resource-group "$RG" --plan "$PLAN" --name "$APP_NAME" --deployment-container-image-name nginx:latest -o none

echo "Enabling managed identity..."
az webapp identity assign --resource-group "$RG" --name "$APP_NAME" -o none
PRINCIPAL_ID=$(az webapp identity show --resource-group "$RG" --name "$APP_NAME" --query principalId -o tsv)
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query id -o tsv)
FOUNDRY_ID=$(az resource show --resource-group "$FOUNDRY_RG" --name "$AI_RESOURCE" --resource-type Microsoft.CognitiveServices/accounts --query id -o tsv)

az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID" -o none
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

az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Cognitive Services User" --scope "$FOUNDRY_ID" -o none
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "Foundry User" --scope "$FOUNDRY_ID" -o none

az webapp log config --resource-group "$RG" --name "$APP_NAME" --docker-container-logging filesystem -o none
az webapp restart --resource-group "$RG" --name "$APP_NAME"

HOST=$(az webapp show --resource-group "$RG" --name "$APP_NAME" --query defaultHostName -o tsv)
echo "Deployment submitted successfully."
echo "Web App: https://$HOST"
echo "Use: az webapp log tail --resource-group \"$RG\" --name \"$APP_NAME\""
