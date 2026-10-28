# Pause and Resume Strategy

## Why stopping the Web App is not the full pause strategy

The paid compute resource is the App Service Plan. A long-idle project can remove the Web App and App Service Plan while preserving the ACR image and Foundry agent.

## What pause.sh preserves

- Hosting resource group
- Azure Container Registry
- Production Docker image and tag
- Microsoft Foundry resource, project and agent
- Source repository

## What pause.sh deletes

- Azure Web App
- App Service Plan

## Identity impact

A system-assigned managed identity belongs to a specific Web App. Deleting the Web App deletes that identity. A newly created Web App receives a new principal ID, so ACR and Foundry role assignments must be reapplied. `resume.sh` performs those assignments.

## Validate after resume

```bash
az webapp config show --resource-group "$RG" --name "$APP_NAME" --query webSocketsEnabled -o tsv
az webapp config show --resource-group "$RG" --name "$APP_NAME" --query linuxFxVersion -o tsv
az role assignment list --assignee-object-id "$PRINCIPAL_ID" --scope "$FOUNDRY_ID" --query "[].roleDefinitionName" -o table
az webapp log tail --resource-group "$RG" --name "$APP_NAME"
```

Then open the HTTPS URL in an InPrivate/Incognito browser and test microphone, Start Session and voice response.
