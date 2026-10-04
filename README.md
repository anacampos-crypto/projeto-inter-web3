# Projeto Banco Inter - Protocolo de Concessão de Crédito Interfinanceiro

Prova de conceito acadêmica para registrar, aceitar e liquidar ofertas de
crédito interfinanceiro overnight em ambiente de testes.

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `docs/maquina-estados-oferta.md` | Especificação da máquina de estados da oferta (estados, gatilhos, guardas, invariantes) |
| `src/interfaces/ICreditInterbankOffer.sol` | Interface: modelo de dados, eventos, erros e funções |
| `src/CreditInterbankOffer.sol` | Contrato de ofertas com cadastro de instituições, limite de crédito e liquidação DvP |
| `src/tokens/BRLToken.sol` | Real tokenizado fictício (ERC-20, 2 casas decimais, mint restrito) — perna financeira |
| `src/tokens/CDIPositionToken.sol` | NFT de posição CDI (ERC-721, mint restrito ao contrato de ofertas) — perna do ativo |
| `script/Deploy.s.sol` | Implanta os três contratos e concede ao contrato de ofertas o papel de minter do NFT |
| `test/CreditInterbankOffer.t.sol` | Suíte Foundry |

## Entregas

- **Semana 1 (14/09–20/09):** máquina de estados, interface e projeto Foundry.
- **Semana 2:** token CDI, contrato de liquidação DvP e testes do caminho feliz.

## Fluxo

1. O admin cadastra as instituições (`registerInstitution`) e define o limite
   de crédito de cada tomador (`setCreditLimit`).
2. O ofertante cria uma oferta direcionada a um tomador (`createOffer`). Só é
   possível ofertar para quem tem limite suficiente.
3. O tomador aceita (`acceptOffer`) ou rejeita (`rejectOffer`). No aceite, na
   mesma transação, o limite é consumido, o BRL tokenizado sai do ofertante
   para o tomador e o NFT de posição é emitido para o ofertante. Se qualquer
   perna falhar, tudo reverte.
4. Antes do aceite, o ofertante pode cancelar (`cancelOffer`). Após a janela de
   validade, qualquer conta pode gravar o vencimento (`expireOffer`).

## Estados da oferta

`Offered → Accepted → Settled` ocorre na mesma transação. A partir de
`Offered`, a oferta também pode seguir para `Cancelled` (pelo ofertante),
`Rejected` (pelo tomador) ou `Expired` (após `expiresAt`). Todos os estados,
exceto `Offered`, são finais. Detalhes em `docs/maquina-estados-oferta.md`.

## Como validar

Requer [Foundry](https://book.getfoundry.sh/getting-started/installation). As
dependências (`forge-std` e `openzeppelin-contracts`) são submódulos:

```bash
git submodule update --init --recursive
forge build
forge test -vv
```

Todos os testes da suíte devem passar.

## Deploy

Exemplo local com Anvil:

```bash
anvil
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key <chave do anvil>
```

Todas as operações on-chain fora do ambiente local devem usar exclusivamente a
testnet Sepolia e ativos simulados (`SEPOLIA_RPC_URL` e `ETHERSCAN_API_KEY` no
`.env`).

## Licença

[MIT](LICENSE)
