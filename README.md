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
| `deployments/*.json` | Endereços gerados por cada deploy (a pasta é criada no primeiro deploy) |
| `test/CreditInterbankOffer.t.sol` | Testes do protocolo: ciclo da oferta, DvP, permissões e erros |
| `test/CreditInterbankOfferEdgeCases.t.sol` | Testes de falha e borda: limites exatos, fronteira da validade, reentrância e estados finais |
| `test/Deploy.t.sol` | Testes do script de deploy |
| `test/fixtures/` | Arquivos de configuração usados só nos testes |
| `broadcast/` | Registro das transações de cada deploy feito com `--broadcast` |
| `.env.example` | Modelo das variáveis de ambiente para a Sepolia |

## Entregas

- **Semana 1 (14/09–20/09):** máquina de estados, interface e projeto Foundry.
- **Semana 2:** token CDI, contrato de liquidação DvP e testes do caminho feliz.
- **Semana 3:** testes de falha e borda, script de deploy parametrizado por ambiente e primeiro deploy verificado na Sepolia.

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

## Contratos na Sepolia

Implantados e verificados no Etherscan em 05/10/2026 (bloco 11852305). Os
endereços também ficam em `deployments/sepolia.json`.

| Contrato | Endereço |
| --- | --- |
| `CreditInterbankOffer` | [`0x2401d88D300dD2CEdB83337bba9Ba29E7269079A`](https://sepolia.etherscan.io/address/0x2401d88D300dD2CEdB83337bba9Ba29E7269079A#code) |
| `BRLToken` | [`0x9591db5fa1345Cc12e7b8F747a3DdAeecc83d25D`](https://sepolia.etherscan.io/address/0x9591db5fa1345Cc12e7b8F747a3DdAeecc83d25D#code) |
| `CDIPositionToken` | [`0xae1C70253946E2a4Cf42c1C979ABD9E8d76AE3c7`](https://sepolia.etherscan.io/address/0xae1C70253946E2a4Cf42c1C979ABD9E8d76AE3c7#code) |

Admin: `0x90FC17b6A24A9cBbb984975a6Ea588b063470695`. Instituições cadastradas no
deploy (ver `script/config/sepolia.json`): duas com limite de R$ 5 mi e R$ 10 mi
em BRLt, e uma cadastrada sem limite.

### Demonstração on-chain

Primeira operação liquidada na Sepolia: oferta nº 1, R$ 1.000.000,00 a 100% do
CDI, overnight, do banco A (`0xf43E…94e9`) para o banco B (`0x38a1…aAFF`).

| Etapa | Transação |
| --- | --- |
| `approve` do BRLt pelo ofertante | [`0xac5f8c4b…`](https://sepolia.etherscan.io/tx/0xac5f8c4b2678129920ef2c91fb677d6c4d3324dc62dc9d63afe23934ecfeb3aa) |
| `createOffer` | [`0x1fcfa5db…`](https://sepolia.etherscan.io/tx/0x1fcfa5db23515922b644a39fa15cec2dc7203a5d01dddbda212025f6a911467d) |
| `acceptOffer` (liquidação DvP) | [`0xe503d1c3…`](https://sepolia.etherscan.io/tx/0xe503d1c3f1dddf19cb0de517e291be9b8be34539c0963243414899782658084f) |

A transação de aceite mostra, no mesmo bloco, a transferência de 1.000.000,00
BRLt do banco A para o banco B e a emissão do NFT de posição nº 1 para o banco A,
além dos eventos `OfferAccepted` e `OfferSettled`.

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
DEPLOY_ENV=sepolia forge script script/Deploy.s.sol --rpc-url sepolia --account deployer --sender <endereço do deployer>
DEPLOY_ENV=sepolia forge script script/Deploy.s.sol --rpc-url sepolia --account deployer --sender <endereço do deployer> --broadcast --verify
```

Sem `--broadcast`, o Foundry não abre o keystore; por isso o `--sender` é
necessário para a simulação saber qual conta é o deployer.

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
