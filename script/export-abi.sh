#!/usr/bin/env bash
# Gera as ABIs versionadas em abi/ a partir dos contratos em src/.
# Rode na raiz do projeto sempre que um contrato mudar:
#   bash script/export-abi.sh
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p abi

for contract in CreditInterbankOffer BRLToken CDIPositionToken; do
  forge inspect "$contract" abi --json > "abi/$contract.json"
  echo "abi/$contract.json atualizado"
done
