# Changelog

## v1.0.0 — 17/10/2026

Primeira versão entregue do protocolo de crédito interfinanceiro overnight,
implantada e verificada na Sepolia.

### Contratos

- `CreditInterbankOffer`: cadastro de instituições (`registerInstitution`,
  `revokeInstitution`), limite de crédito por tomador (`setCreditLimit`) e
  ciclo da oferta (`createOffer`, `acceptOffer`, `rejectOffer`, `cancelOffer`,
  `expireOffer`).
- Liquidação DvP atômica no aceite: o BRLt vai do ofertante para o tomador e o
  NFT de posição é emitido para o ofertante na mesma transação.
- `BRLToken`: real tokenizado fictício (ERC-20, 2 casas decimais, mint restrito).
- `CDIPositionToken`: NFT de posição (ERC-721, `tokenId` igual ao `offerId`).
- Estados da oferta: `Offered`, `Accepted` (transitório), `Settled`,
  `Cancelled`, `Expired` e `Rejected`.

### Sepolia

| Contrato | Endereço |
| --- | --- |
| `CreditInterbankOffer` | `0x2401d88D300dD2CEdB83337bba9Ba29E7269079A` |
| `BRLToken` | `0x9591db5fa1345Cc12e7b8F747a3DdAeecc83d25D` |
| `CDIPositionToken` | `0xae1C70253946E2a4Cf42c1C979ABD9E8d76AE3c7` |

Primeira operação liquidada on-chain: oferta nº 1 (ver README, "Demonstração
on-chain").

### Integração

- ABIs versionadas em `abi/` e script `script/export-abi.sh` para regenerá-las.
- Guia de integração em `docs/guia-integracao.md`.
- Endereços e bloco inicial em `deployments/sepolia.json`.

### Qualidade

- 64 testes: ciclo da oferta, DvP, permissões, erros, casos de borda
  (limites exatos, fronteira da validade, reentrância) e script de deploy.

### Fora desta versão

- Liquidação de volta em D+1 (o limite consumido é recomposto pelo admin).
- Garantia em título público.
- Ocultação de ofertas e comprovante para a Selic, que ficam no backend e no
  frontend.
