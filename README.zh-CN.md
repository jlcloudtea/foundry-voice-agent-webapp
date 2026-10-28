# 将 Microsoft Foundry Voice Agent 部署为公开 Web App

> 中文指南。English: [README.md](README.md)

本教程介绍如何把一个已经存在并测试成功的 Microsoft Foundry Voice Agent，使用 Azure App Service、Azure Container Registry、Managed Identity、Python/FastAPI、React 和 WebSocket 部署成公开语音网页。

## 最终架构

```text
学生 / 用户
    |
    | 公开 HTTPS + 麦克风
    v
Azure App Service
  React + Python/FastAPI + WebSocket
    |
    | System-assigned Managed Identity
    v
Microsoft Foundry
    |
    v
已有 Voice Agent
    |
    v
语音回复
```

最终用户不需要 Azure RBAC、Azure Portal 权限、API Key 或你的 Azure 登录凭据。服务器通过 Managed Identity 访问 Azure。

## 前置条件

- Azure 订阅，包括在相关服务可用情况下的 Azure for Students
- 已有可正常运行的 Microsoft Foundry Project 和 Voice Agent
- GitHub 账号
- GitHub Codespaces 或其他 Linux 开发环境
- Azure CLI
- Docker
- 有权限创建 Resource Group、ACR、App Service、Managed Identity 和 RBAC assignment

部署前首先在 Microsoft Foundry 的 Voice Preview 中确认 Agent 可以正常进行双向语音交流。

## 1. 获取 Microsoft Voice Live 示例

官方示例：

[Microsoft Foundry Voice Live samples](https://github.com/microsoft-foundry/voicelive-samples)

```bash
git clone https://github.com/microsoft-foundry/voicelive-samples.git
cd voicelive-samples/voice-live-universal-assistant
```

本教程使用：

```text
Frontend: React + Vite
Backend: Python + FastAPI
```

## 2. 配置 Agent Mode

```bash
cd python
cp .env.sample .env
```

修改 `.env`：

```env
AZURE_VOICELIVE_ENDPOINT=https://<AI-RESOURCE-NAME>.services.ai.azure.com/
AZURE_VOICELIVE_API_KEY=
VOICELIVE_MODE=agent
AZURE_VOICELIVE_AGENT_NAME=<YOUR-AGENT-NAME>
AZURE_VOICELIVE_PROJECT=<YOUR-PROJECT-NAME>
```

不要把密码、token、API key、client secret 等提交到公共 GitHub repository。

## 3. 登录 Azure

```bash
az login --use-device-code
az account show --output table
```

如需切换订阅：

```bash
az account set --subscription "<SUBSCRIPTION-NAME-OR-ID>"
```

验证 AI Resource：

```bash
az resource show \
  --resource-group "<FOUNDRY-RESOURCE-GROUP>" \
  --name "<AI-RESOURCE-NAME>" \
  --resource-type Microsoft.CognitiveServices/accounts \
  --output table
```

## 4. 本地验证

Python：

```bash
cd python
python3 -m pip install -r requirements.txt
```

Frontend：

```bash
cd ../frontend
npm install
npm run build
```

运行 integrated application：

```bash
cd ../python
python3 -m uvicorn app:app --host 0.0.0.0 --port 8000
```

使用 Codespaces 时打开 forwarded port `8000`，允许麦克风，启动 Session，并确认 Voice Agent 可以正常语音回复。

### Codespaces 常见问题

如果 frontend 单独运行在 `5173`，Python 在 `8000`，并出现：

```text
Chat session ID: N/A
```

请停止独立 Vite server，执行：

```bash
cd frontend
npm run build
```

然后使用 Python backend 在 `8000` 提供完整应用。

## 5. 定义部署变量

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

## 6. Resource Group 和 ACR

```bash
az group create --name "$RG" --location "$LOCATION"

az acr create \
  --resource-group "$RG" \
  --name "$ACR_NAME" \
  --sku Basic
```

## 7. Build 并 Push Docker Image

在 `voice-live-universal-assistant` 根目录：

```bash
docker build \
  -f Dockerfile.python \
  -t "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG" \
  .

az acr login --name "$ACR_NAME"

docker push "$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"
```

## 8. 创建 Linux App Service Plan

```bash
az appservice plan create \
  --name "$PLAN" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --is-linux \
  --sku B1
```

B1 仅作为小型教学/演示部署示例。正式使用前请根据实际 workload 和费用要求选择 tier。

## 9. 创建 Web App

```bash
az webapp create \
  --resource-group "$RG" \
  --plan "$PLAN" \
  --name "$APP_NAME" \
  --deployment-container-image-name nginx:latest
```

`nginx:latest` 只作为临时 placeholder。

## 10. 开启 System Assigned Managed Identity

```bash
az webapp identity assign \
  --resource-group "$RG" \
  --name "$APP_NAME"

PRINCIPAL_ID=$(az webapp identity show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query principalId -o tsv)
```

## 11. 允许 App Service 从 ACR Pull Image

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

## 12. 配置生产 Docker Image

```bash
IMAGE="$ACR_NAME.azurecr.io/$IMAGE_REPO:$IMAGE_TAG"

az webapp config container set \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --container-image-name "$IMAGE" \
  --container-registry-url "https://$ACR_NAME.azurecr.io"
```

## 13. 配置 Voice Live

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

## 14. 开启 WebSocket 和 HTTPS

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

## 15. 给 Managed Identity Foundry 权限

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

## 16. Logging 和 Restart

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

## 17. 公网测试

取得 hostname：

```bash
az webapp show \
  --resource-group "$RG" \
  --name "$APP_NAME" \
  --query defaultHostName -o tsv
```

打开 `https://<YOUR-WEBAPP-NAME>.azurewebsites.net`：

1. Allow microphone
2. Start Session
3. Speak to Agent
4. 检查 transcription
5. 检查 Agent response
6. 检查 voice playback

然后使用 InPrivate/Incognito 浏览器，在不登录 Azure 的情况下重复测试匿名访问。

## 安全建议

- 不要在 frontend JavaScript 中放 Azure credentials、API keys、client secrets、tokens 或 ACR passwords。
- `.env` 不要进入 Git。
- 使用 HTTPS。
- 使用 Managed Identity 访问 Azure Services。
- 公网 AI voice endpoint 建议增加 rate limit / abuse protection。
- 正式发布前检查所在组织的 AI、安全、隐私及发布政策。

## 成本

可能产生费用的部分包括：Foundry/Voice Live/model usage、App Service、ACR、logging 和 network usage。教学部署建议同时设置 Azure Budget 和成本提醒。

## Cleanup

如果 hosting resources 全部独立放在 `$RG`：

```bash
az group delete --name "$RG" --yes
```

注意：如果 Foundry Project 在其他 Resource Group，不要误删 Foundry 所在 Resource Group。

## Troubleshooting

参见 [docs/troubleshooting.md](docs/troubleshooting.md)。

## 声明

本项目用于学习、教学和可重复部署演示。Microsoft Foundry、Voice Live APIs 和 Azure 平台能力未来可能变化。生产部署之前请查看最新 Microsoft 文档、安全要求和价格。

## 暂停与恢复：降低闲置 Hosting 成本

仅仅 Stop Web App 并不能移除付费 App Service Plan。长时间不用时，可以运行暂停脚本删除 Web App 和 App Service Plan，同时保留 ACR 中的生产 Docker Image 以及独立 Resource Group 中的 Microsoft Foundry Agent。

### 暂停

```bash
export RG="rg-VoiceAgent"
export PLAN="plan-VoiceAgent"
export APP_NAME="<YOUR-UNIQUE-WEBAPP-NAME>"
./scripts/pause.sh
```

暂停脚本保留 ACR、生产 Docker Image、Foundry Resource/Project/Agent 和源代码仓库；删除 Web App 和付费 App Service Plan。

### 恢复

```bash
export RG="rg-VoiceAgent"
export LOCATION="eastus"
export ACR_NAME="<YOUR-ACR-NAME>"
export PLAN="plan-VoiceAgent"
export APP_NAME="<YOUR-UNIQUE-WEBAPP-NAME>"
export AI_RESOURCE="<AI-RESOURCE-NAME>"
export FOUNDRY_RG="<FOUNDRY-RESOURCE-GROUP>"
export FOUNDRY_PROJECT="<FOUNDRY-PROJECT-NAME>"
export AGENT_NAME="<VOICE-AGENT-NAME>"
export IMAGE_REPO="voicelive-web"
export IMAGE_TAG="v1"
./scripts/resume.sh
```

重新创建的 Web App 会获得新的 Managed Identity principal。恢复脚本会给新 identity 重新分配 `AcrPull`、`Cognitive Services User` 和 `Foundry User`。

参见 [暂停与恢复运维说明](docs/pause-resume.md)。
## 可选功能：Enhanced Student UI

项目提供经过测试的学生版 Troubleshooting 界面作为可选增强功能。

包括：

- 对学生隐藏技术设置
- New Chat
- 10 分钟倒计时及自动结束
- Transcript 下载
- 同时包含学生和 AI Assistant 声音的完整会话录音
- 录音保存在浏览器本地，本示例不使用 Azure Storage 保存录音

已测试源码版本：`jlcloudtea/voicelive-samples` 中的 `troubleshooting-demo-v1.0.0`。

详见 [Enhanced Student UI](docs/enhanced-student-ui.md)。
