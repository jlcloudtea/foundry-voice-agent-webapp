# Optional Enhancement: Student-Focused Troubleshooting UI

This optional enhancement builds on the standard Microsoft Foundry Voice Live Universal Assistant deployment described in this repository.

It is intended for teaching and demonstration scenarios where learners should interact with the voice agent without changing technical connection settings.

## Tested version

Companion source repository:

- Fork: `jlcloudtea/voicelive-samples`
- Branch: `mixed-session-audio`
- Tested tag: `troubleshooting-demo-v1.0.0`
- Tested commit: `4ed41b5`

The enhanced UI was tested using the Python/FastAPI backend and the built React frontend served through the same application on port 8000.

## Features

The enhanced interface adds:

- Student-focused **AI Troubleshooting Demo** presentation
- Technical settings removed from the student interface
- **New chat** retained
- 10-minute session limit
- Visible countdown timer
- Automatic session stop when the timer reaches `00:00`
- Transcript download as `.txt`
- Full-conversation browser recording
- Student microphone and assistant playback mixed into the downloaded recording
- Browser-native audio download, normally WebM/Opus where supported
- Browser-local recording only; this sample does not upload the recording to Azure storage

## Recommended deployment flow

1. Complete the main deployment guide first and verify the standard Voice Live Universal Assistant works locally and in Azure App Service.
2. Use the companion fork and check out the tested release:

```bash
git clone https://github.com/jlcloudtea/voicelive-samples.git
cd voicelive-samples
git checkout troubleshooting-demo-v1.0.0
cd voice-live-universal-assistant
```

3. Build the frontend:

```bash
cd frontend
npm install
npm run build
```

4. Test locally through the Python backend:

```bash
cd ../python
python3 -m pip install -r requirements.txt
python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
```

5. Verify microphone access, voice conversation, countdown, automatic/manual stop, transcript download and conversation-audio download.
6. Build a new Docker image tag instead of overwriting a known-good image.
7. Push the new image to the existing Azure Container Registry and point the existing App Service at the new tag.
8. Test the public URL again, including an InPrivate/Incognito test without an Azure sign-in.

## Student controls

The student-facing version is intentionally limited to session controls such as:

- Start/stop session
- New chat
- Microphone controls
- Transcript/captions
- Countdown timer
- Download transcript
- Download conversation audio

Agent, project, model, Foundry resource and identity settings remain deployment configuration rather than student-selectable controls.

## 10-minute session timer

The session duration is configured in `frontend/src/App.tsx`:

```typescript
const SESSION_SECONDS = 10 * 60;
```

For a quick automatic-stop test during development, temporarily use a short value such as `30`, rebuild, test the full end-of-session workflow, and restore `10 * 60` before publishing.

## Recording design

The enhanced version mixes two application audio paths into a browser recording destination:

```text
Student microphone -----\
                         > Web Audio recording mix -> MediaRecorder -> download
Assistant playback -----/
```

The microphone is not routed to the speakers by the mixer. The assistant audio continues to use the application's normal playback path while also being routed to the recording mix.

For clearer recordings, a headset is recommended because loudspeaker output can otherwise be picked up acoustically by the microphone in addition to the direct assistant-audio path.

## Privacy and data handling

The sample keeps the recording in browser memory for download. It does not implement Azure Blob Storage or server-side recording retention.

Before using recording with learners, add an appropriate recording/privacy notice and follow the policies that apply to your organisation, course and jurisdiction.

Never expose Azure credentials, access tokens, API keys, client secrets or ACR passwords in frontend code.

## Updating an existing App Service

Use a new image tag, for example:

```bash
ACR_NAME="<YOUR-ACR-NAME>"
IMAGE_REPO="voicelive-web"
IMAGE_TAG="troubleshooting-demo-v1"

cd /path/to/voicelive-samples/voice-live-universal-assistant

docker build \
  -f Dockerfile.python \
  -t "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG" \
  .

az acr login --name "$ACR_NAME"
docker push "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"
```

Verify the image tag exists before updating App Service:

```bash
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "$IMAGE_REPO" \
  -o table
```

Then configure the existing Web App:

```bash
APP_NAME="<YOUR-WEBAPP-NAME>"
RG="<YOUR-HOSTING-RESOURCE-GROUP>"
REGISTRY_URL="https://${ACR_NAME}.azurecr.io"

az webapp config container set \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --container-image-name "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG" \
  --container-registry-url "$REGISTRY_URL"

az webapp restart \
  --resource-group "$RG" \
  --name "$APP_NAME"
```

## Rollback

Keep the previous known-good ACR image tag. If a new frontend build fails in App Service, point the Web App back to the previous image tag and restart the app.

A `503 Service Unavailable` immediately after an image change can be caused by App Service being configured with an image tag that has not been pushed to ACR. Verify the requested tag is present before changing the Web App container configuration.

## Relationship to the main guide

This enhancement is optional. The main deployment guide remains the recommended starting point because it establishes and validates the Azure architecture first:

```text
Public browser
    -> Azure App Service
    -> Managed Identity
    -> Microsoft Foundry Voice Agent
```

Apply the enhanced student UI only after the baseline deployment is working.
