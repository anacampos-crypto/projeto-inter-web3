# Projeto Banco Inter - Protocolo de Concessão de Crédito Interfinanceiro

Prova de conceito acadêmica para registrar, aceitar e liquidar ofertas de
crédito interfinanceiro overnight em ambiente de testes.

## Escopo da Semana 1 (14/09–20/09)

- Máquina de estados da oferta: `docs/maquina-estados-oferta.md`
- Interface Solidity: `src/interfaces/ICreditInterbankOffer.sol`
- Projeto Foundry com teste de exemplo: `test/CreditInterbankOffer.t.sol`

Esta etapa não inclui a implementação do token CDI nem a liquidação DvP real;
esses itens pertencem à Semana 2. O contrato em teste é um mock mínimo para
demonstrar que a interface pode ser compilada e exercitada.

## Estados da oferta

`Offered → Accepted → Settled` ocorre na mesma transação. Alternativamente,
uma oferta em `Offered` pode seguir para `Cancelled` pelo ofertante.

## Como validar

Requer [Foundry](https://book.getfoundry.sh/getting-started/installation) e a
biblioteca `forge-std`:

```bash
forge build
forge test -vv
```

O resultado esperado é três testes aprovados. Todas as futuras operações
on-chain devem usar exclusivamente a testnet Sepolia e ativos simulados.

## Licença

[MIT](LICENSE)
