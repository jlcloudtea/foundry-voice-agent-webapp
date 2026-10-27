# Troubleshooting

## `Chat session ID: N/A`

If the React/Vite frontend is running separately on port 5173 while Python is running on port 8000, the browser/WebSocket route may not work correctly in some forwarded development environments.

Try the integrated build:

```bash
cd frontend
npm run build
cd ../python
python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
```

Open port 8000.

## Web page opens but Start Session fails

Enable and inspect App Service logs:

```bash
az webapp log tail --resource-group "$RG" --name "$APP_NAME"
```

Verify the application settings:

```bash
az webapp config appsettings list \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  -o table
```

Required values include:

```text
WEBSITES_PORT=8000
VOICELIVE_MODE=agent
AZURE_VOICELIVE_AGENT_NAME=<agent>
AZURE_VOICELIVE_PROJECT=<project>
AZURE_VOICELIVE_ENDPOINT=<resource endpoint>
```

Verify WebSockets:

```bash
az webapp config show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query webSocketsEnabled -o tsv
```

Expected: `true`.

## Container image cannot be pulled

Verify the Web App identity has `AcrPull` on the registry:

```bash
az role assignment list \
  --assignee-object-id "$PRINCIPAL_ID" \
  --scope "$ACR_ID" \
  -o table
```

Verify App Service uses managed identity for ACR:

```bash
az webapp config show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query acrUseManagedIdentityCreds -o tsv
```

Expected: `true`.

## Foundry authentication fails

Inspect assignments on the Azure AI resource:

```bash
az role assignment list \
  --assignee-object-id "$PRINCIPAL_ID" \
  --scope "$FOUNDRY_ID" \
  --query "[].roleDefinitionName" \
  -o table
```

The validated reference deployment used:

```text
Cognitive Services User
Foundry User
```

## Endpoint accidentally contains HTML

If an endpoint was copied from a rich-text interface, verify the stored setting is a clean URL rather than an HTML anchor.

Safer construction pattern:

```bash
AI_RESOURCE="<AI-RESOURCE-NAME>"
VOICE_ENDPOINT="https://${AI_RESOURCE}.services.ai.azure.com/"
```

Then set the application value from `$VOICE_ENDPOINT`.

## Container does not start

Check the configured image:

```bash
az webapp config show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query linuxFxVersion -o tsv
```

Check logs:

```bash
az webapp log tail \
  --resource-group "$RG" \
  --name "$APP_NAME"
```
