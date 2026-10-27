#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${RG:-}" ]]; then
  echo "Set RG to the hosting resource group before cleanup." >&2
  echo 'Example: export RG="rg-VoiceAgent"' >&2
  exit 1
fi

echo "This will delete hosting resource group: $RG"
echo "Ensure your Foundry project is NOT stored in this resource group."
read -r -p "Type DELETE to continue: " answer
[[ "$answer" == "DELETE" ]] || { echo "Cancelled."; exit 0; }

az group delete --name "$RG" --yes
