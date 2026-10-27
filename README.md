# Deploy a Microsoft Foundry Voice Agent as a Public Web App

> English guide. 中文版本: [README.zh-CN.md](README.zh-CN.md)

This tutorial deploys an existing Microsoft Foundry Voice Agent as a public voice-enabled web application using Azure App Service, Azure Container Registry, Managed Identity, Python/FastAPI, React and WebSockets.

## Architecture

```text
User / Student
      |
      | Public HTTPS + microphone
      v
Azure App Service
  React UI + Python/FastAPI + WebSocket
      |
      | System-assigned Managed Identity
      v
Microsoft Foundry
      |
      v
Existing Voice Agent
      |
      v
Voice response
```

The browser does not need Azure RBAC, an Azure account, an API key, or your Azure credentials. The server authenticates to Azure with Managed Identity.

## Prerequisites

- An active Azure subscription, including Azure for Students where the required services are available
- A working Microsoft Foundry project and existing Voice Agent
- GitHub account and GitHub Codespaces, or another Linux development environment
- Azure CLI
- Docker
- Permission to create resource groups, Azure Container Registry, App Service Plan, Web App, managed identity and RBAC assignments

Before deployment, verify the agent works in the Foundry voice preview.

## 1. Clone Microsoft's Voice Live sample

Microsoft sample repository:

[Microsoft Foundry Voice Live samples](https://github.com/microsoft-foundry/voicelive-samples)

```bash
git clone https://github.com/microsoft-foundry/voicelive-samples.git
cd voicelive-samples/voice-live-universal-assistant
```

This guide uses the React/Vite frontend and Python/FastAPI backend.

## 2. Configure agent mode

```bash
cd python
cp .env.sample .env
```

Edit `.env`:

```env
AZURE_VOICELIVE_ENDPOINT=https://<AI-RESOURCE-NAME>.services.ai.azure.com/
AZURE_VOICELIVE_API_KEY=
VOICELIVE_MODE=agent
AZURE_VOICELIVE_AGENT_NAME=<YOUR-AGENT-NAME>
AZURE_VOICELIVE_PROJECT=<YOUR-PROJECT-NAME>
```

Never commit credentials, access tokens, passwords, API keys or client secrets.

## 3. Sign in to Azure

```bash
az login --use-device-code
az account show --output table
```

If required:

```bash
az account set --subscription "<SUBSCRIPTION-NAME-OR-ID>"
```

Confirm access to the Azure AI resource:

```bash
az resource show \
  --resource-group "<FOUNDRY-RESOURCE-GROUP>" \
  --name "<AI-RESOURCE-NAME>" \
  --resource-type Microsoft.CognitiveServices/accounts \
  --output table
```

## 4. Test locally first

Install Python dependencies:

```bash
cd python
python3 -m pip install -r requirements.txt
```

Build the frontend:

```bash
cd ../frontend
npm install
npm run build
```

Start the integrated application:

```bash
cd ../python
python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
```

If using Codespaces, open forwarded port `8000`, allow microphone access, start a session and verify two-way voice conversation.

### Codespaces troubleshooting

If a separate Vite server on port `5173` produces `Chat session ID: N/A`, stop Vite, run `npm run build`, and use the Python-hosted site on port `8000`.

## 5. Define deployment variables

```bash
RG="rg-VoiceAgent"
LOCATION="eastus"
ACR_NAME="<UNIQUE-ACR-NAME>"
PLAN="plan-VoiceAgent"
APP_NAME="<UNIQUE-WEBAPP-NAME>"
AI_RESOURCE="<AI-RESOURCE-NAME>"
FOUNDRY_RG="<FOUNDRY-RESOURCE-GROUP>"
FOUNDRY_PROJECT="<FOUNDRY-PROJECT-NAME>"
AGENT_NAME="<VOICE-AGENT-NAME>"
IMAGE_REPO="voicelive-web"
IMAGE_TAG="v1"
```

## 6. Create Resource Group and ACR

```bash
az group create --name "$RG" --location "$LOCATION"

az acr create \
  --resource-group "$RG" \
  --name "$ACR_NAME" \
  --sku Basic
```

## 7. Build and push the production image

From `voice-live-universal-assistant`:

```bash
docker build \
  -f Dockerfile.python \
  -t "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG" \
  .

az acr login --name "$ACR_NAME"

docker push "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"
```

Verify:

```bash
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "$IMAGE_REPO" \
  -o table
```

## 8. Create Linux App Service Plan

```bash
az appservice plan create \
  --name "$PLAN" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --is-linux \
  --sku B1
```

B1 is an example for a small demonstration deployment. Choose a tier appropriate for your workload and budget.

## 9. Create the Web App

```bash
az webapp create \
  --resource-group "$RG" \
  --plan "$PLAN" \
  --name "$APP_NAME" \
  --deployment-container-image-name nginx:latest
```

The nginx image is only a temporary placeholder.

## 10. Enable system-assigned Managed Identity

```bash
az webapp identity assign \
  --resource-group "$RG" \
  --name "$APP_NAME"

PRINCIPAL_ID=$(az webapp identity show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query principalId -o tsv)
```

## 11. Permit Managed Identity to pull from ACR

```bash
ACR_ID=$(az acr show \
  --name "$ACR_NAME" \
  --resource-group "$RG" \
  --query id -o tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role AcrPull \
  --scope "$ACR_ID"

az webapp config set \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --generic-configurations '{"acrUseManagedIdentityCreds": true}'
```

## 12. Configure the production container image

```bash
IMAGE="$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"

az webapp config container set \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --container-image-name "$IMAGE" \
  --container-registry-url "https://$ACR_NAME.azurecr.io"
```

## 13. Configure Voice Live application settings

```bash
VOICE_ENDPOINT="https://${AI_RESOURCE}.services.ai.azure.com/"

az webapp config appsettings set \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --settings \
    WEBSITES_PORT=8000 \
    AZURE_VOICELIVE_ENDPOINT="$VOICE_ENDPOINT" \
    VOICELIVE_MODE=agent \
    AZURE_VOICELIVE_AGENT_NAME="$AGENT_NAME" \
    AZURE_VOICELIVE_PROJECT="$FOUNDRY_PROJECT"
```

## 14. Enable WebSockets and HTTPS

```bash
az webapp config set \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --web-sockets-enabled true

az webapp update \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --https-only true
```

## 15. Grant the Web App access to Foundry

```bash
FOUNDRY_ID=$(az resource show \
  --resource-group "$FOUNDRY_RG" \
  --name "$AI_RESOURCE" \
  --resource-type Microsoft.CognitiveServices/accounts \
  --query id -o tsv)

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Cognitive Services User" \
  --scope "$FOUNDRY_ID"

az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Foundry User" \
  --scope "$FOUNDRY_ID"
```

Verify:

```bash
az role assignment list \
  --assignee-object-id "$PRINCIPAL_ID" \
  --scope "$FOUNDRY_ID" \
  --query "[].roleDefinitionName" \
  -o table
```

## 16. Enable logs and restart

```bash
az webapp log config \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --docker-container-logging filesystem

az webapp restart \
  --resource-group "$RG" \
  --name "$APP_NAME"

az webapp log tail \
  --resource-group "$RG" \
  --name "$APP_NAME"
```

A healthy deployment should show the container start successfully and HTTP requests returning successfully.

## 17. Test public and anonymous access

Get the host name:

```bash
az webapp show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query defaultHostName -o tsv
```

Open `https://<YOUR-WEBAPP-NAME>.azurewebsites.net`, allow the microphone, select **Start Session**, and test voice input/output.

Repeat in an InPrivate/Incognito browser without signing in to Azure.

## Security notes

- Do not expose Azure credentials, ACR passwords, API keys, client secrets or access tokens in frontend code.
- Keep `.env` files out of Git.
- Use HTTPS.
- Use Managed Identity for Azure service access.
- Consider rate limiting/abuse controls before sharing a public AI voice endpoint widely.
- Review your organisation's security, privacy and AI publishing requirements before production use.

## Costs

This architecture can incur charges for Microsoft Foundry/Voice Live/model usage, App Service, Azure Container Registry, logging and networking. Review Azure Cost Management and configure budgets/alerts appropriate to your subscription.

## Cleanup

If the hosting resources are isolated in `$RG` and no longer needed:

```bash
az group delete --name "$RG" --yes
```

Do not delete the resource group containing your Foundry project unless you intentionally want to remove the Foundry resources as well.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## Disclaimer

This repository is intended for learning, demonstration and reproducible deployment guidance. Microsoft Foundry, Voice Live APIs and Azure platform behaviour can change. Review current Microsoft documentation, security guidance and pricing before production use.
