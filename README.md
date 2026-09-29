# Projeto Banco Inter — Protocolo de Concessão de Crédito Interfinanceiro

Prova de conceito acadêmica em Solidity para registrar, aceitar e liquidar
ofertas direcionadas de crédito interfinanceiro overnight em ambiente de testes.

## Escopo implementado

O fluxo atual contempla:

- cadastro e revogação de carteiras institucionais pelo administrador;
- definição e consumo de limite de crédito por instituição;
- criação de oferta direcionada, com taxa CDI, prazo e janela de validade;
- aceite, rejeição, cancelamento e expiração de ofertas;
- liquidação atômica DvP no aceite: transferência de BRL tokenizado ao tomador e
  emissão de um NFT de posição ao credor;
- reversão integral quando qualquer perna da liquidação falha.

O pagamento do empréstimo em D+1 e a queima do NFT ainda estão fora do escopo.
Toda operação on-chain deve usar exclusivamente testnet e ativos simulados.

## Contratos

| Arquivo | Responsabilidade |
| --- | --- |
| `src/CreditInterbankOffer.sol` | Cadastro, limites, ciclo da oferta e liquidação DvP |
| `src/interfaces/ICreditInterbankOffer.sol` | Tipos, eventos, erros e interface pública |
| `src/tokens/BRLToken.sol` | ERC-20 fictício com duas casas decimais; 1 unidade equivale a 1 centavo |
| `src/tokens/CDIPositionToken.sol` | ERC-721 que representa a posição de crédito liquidada |
| `script/Deploy.s.sol` | Deploy dos três contratos e concessão do papel de emissão do NFT |

A máquina de estados, suas guardas e invariantes estão detalhadas em
[`docs/maquina-estados-oferta.md`](docs/maquina-estados-oferta.md).

## Pré-requisitos e instalação

Instale o [Foundry](https://getfoundry.sh/getting-started/installation). O projeto
é compilado com Solidity 0.8.24; o Forge baixa essa versão automaticamente na
primeira execução.

Depois de clonar o repositório, instale as dependências registradas em
`foundry.lock`:

```bash
forge install
```

As dependências esperadas são `forge-std` v1.16.2 e
`openzeppelin-contracts` v5.7.0. A pasta `lib/` não é versionada; o
`foundry.lock` fixa as revisões instaladas e `remappings.txt` configura os
imports usados pelos contratos.

## Validação

```bash
forge build
forge test -vv
```

Na revisão de 28/09/2026, o resultado esperado é uma suíte com 34 testes
aprovados, sem falhas ou testes ignorados. Ela cobre criação, permissões,
limites, aceite e DvP, rollback da liquidação, rejeição, cancelamento,
expiração e regras dos tokens.

Para verificar também a formatação Solidity sem alterar arquivos:

```bash
forge fmt --check
```

## Deploy local

Com um nó Anvil em execução, use uma chave apenas de desenvolvimento:

```bash
anvil
forge script script/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key <chave-do-anvil>
```

O deploy cria os três contratos e autoriza `CreditInterbankOffer` a emitir o
NFT de posição. O administrador ainda precisa cadastrar as instituições,
definir limites e emitir o saldo inicial de BRL tokenizado.

## Licença

[MIT](LICENSE)
