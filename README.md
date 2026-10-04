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
| `script/Deploy.s.sol` | Deploy parametrizado por ambiente (ver [Deploy](#deploy)) |
| `script/config/*.json` | Configuração de cada ambiente de deploy (rede, admin, instituições) |
| `deployments/*.json` | Endereços gerados por cada deploy |
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

O script `script/Deploy.s.sol` implanta os três contratos, concede ao contrato
de ofertas o papel de minter do NFT e prepara o ambiente (cadastro de
instituições, limites e saldo inicial de BRLt). Tudo o que muda entre ambientes
fica em `script/config/<ambiente>.json`, e o ambiente é escolhido pela variável
`DEPLOY_ENV` (padrão: `local`).

### Configuração do ambiente

```json
{
  "chainId": 11155111,
  "admin": "0x...",
  "institutions": [
    { "wallet": "0x...", "creditLimit": 500000000, "brlMint": 1000000000 }
  ]
}
```

| Campo | Descrição |
| --- | --- |
| `chainId` | Rede esperada. O script aborta se o RPC apontar para outra rede. |
| `admin` | Opcional. Admin final do protocolo; se diferente de quem assina, os papéis administrativos são transferidos a ele e removidos do deployer ao final. Se omitido, quem assina permanece admin. |
| `institutions` | Carteiras cadastradas no deploy. `creditLimit` e `brlMint` em centavos de BRLt (`100` = R$ 1,00); use `0` para pular. |

Para um novo ambiente, basta criar `script/config/<nome>.json` e rodar com
`DEPLOY_ENV=<nome>`.

O resultado é gravado em `deployments/<ambiente>.json`, com os endereços,
`chainId`, deployer, admin e `startBlock`. Deploys locais ficam fora do git.

### Local (Anvil)

`script/config/local.json` usa as contas padrão do Anvil: a conta 0 assina o
deploy, as contas 1 e 2 entram com limite de R$ 5 mi e R$ 10 mi em BRLt, e a
conta 3 entra cadastrada, mas sem limite.

```bash
anvil
# em outro terminal (chave pública da conta 0 do Anvil)
DEPLOY_ENV=local forge script script/Deploy.s.sol --rpc-url local --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### Sepolia

1. `cp .env.example .env` e preencha `SEPOLIA_RPC_URL` e `ETHERSCAN_API_KEY`
   (o Foundry carrega o `.env` automaticamente).
2. Importe a carteira de deploy em um keystore criptografado (evita chave em
   texto puro): `cast wallet import deployer --interactive`.
3. Preencha `script/config/sepolia.json` com o `admin` e as carteiras das
   instituições, e garanta saldo de SepoliaETH na carteira de deploy.
4. Simule sem `--broadcast` e, se estiver tudo certo, implante e verifique:

```bash
DEPLOY_ENV=sepolia forge script script/Deploy.s.sol --rpc-url sepolia --account deployer
DEPLOY_ENV=sepolia forge script script/Deploy.s.sol --rpc-url sepolia --account deployer --broadcast --verify
```

### Após o deploy

O script não executa ações que exigem a chave das instituições. Para que uma
oferta possa ser liquidada, cada ofertante precisa autorizar o contrato de
ofertas a movimentar seu BRLt:

```bash
cast send <BRLToken> "approve(address,uint256)" <CreditInterbankOffer> <valor> --rpc-url <rede> --account <ofertante>
```

Todas as operações on-chain fora do ambiente local devem usar exclusivamente a
testnet Sepolia e ativos simulados.

## Licença

[MIT](LICENSE)
