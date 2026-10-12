# Guia de integração — contratos na Sepolia

Como o backend e o frontend chamam cada função do protocolo e quais eventos
devem observar. A especificação dos estados está em
[`maquina-estados-oferta.md`](maquina-estados-oferta.md); as ABIs estão em
[`abi/`](../abi).

## 1. Endereços e artefatos

| Item | Valor |
| --- | --- |
| Rede | Sepolia (`chainId` 11155111) |
| `CreditInterbankOffer` | `0x2401d88D300dD2CEdB83337bba9Ba29E7269079A` |
| `BRLToken` (BRLt) | `0x9591db5fa1345Cc12e7b8F747a3DdAeecc83d25D` |
| `CDIPositionToken` (CDIP) | `0xae1C70253946E2a4Cf42c1C979ABD9E8d76AE3c7` |
| Bloco inicial para ler eventos | `11852299` (`startBlock` em `deployments/sepolia.json`) |
| ABIs | `abi/CreditInterbankOffer.json`, `abi/BRLToken.json`, `abi/CDIPositionToken.json` |

Na prática, o backend e o frontend só precisam falar com o
`CreditInterbankOffer` e com o `BRLToken` (para o `approve` e para ler saldos).
O `CDIPositionToken` é emitido pelo próprio contrato de ofertas na liquidação e
só precisa ser lido (por exemplo, `ownerOf`).

## 2. Unidades

Todos os números são inteiros (`uint256`). Converta só na hora de exibir.

| Campo | Unidade | Exemplo |
| --- | --- | --- |
| `amount`, limites, saldos de BRLt | Centavos (o BRLt tem 2 casas decimais) | `100000000` = R$ 1.000.000,00 |
| `rateCDI` | Percentual do CDI em pontos-base | `10000` = 100% do CDI |
| `term` | Dias do empréstimo | `1` = overnight |
| `validityWindow` | Segundos, contados a partir da criação | `3600` = 1 hora |
| `createdAt`, `settledAt`, `expiresAt`, `timestamp` | Segundos Unix (horário do bloco) | `1791247068` |
| `offerId` | Sequencial a partir de 1 | `1` |
| `positionTokenId` | Igual ao `offerId` | `1` |

## 3. Pré-requisitos de cada operação

Antes de uma oferta poder ser liquidada:

1. **O admin cadastra as carteiras** dos bancos com `registerInstitution`.
2. **O admin define o limite do tomador** com `setCreditLimit`.
3. **O ofertante tem saldo de BRLt** (o admin emite com `BRLToken.mint`).
4. **O ofertante autoriza o contrato de ofertas a mover o BRLt dele**:
   `BRLToken.approve(CreditInterbankOffer, valor)`. Sem esse passo, o aceite
   reverte com `ERC20InsufficientAllowance`.

O passo 4 é assinado pela carteira do próprio banco ofertante. No frontend, vale
pedir o `approve` logo antes do `createOffer`, ou na primeira vez que o banco
for ofertar.

## 4. Funções de escrita

Todas exigem uma transação assinada pela carteira indicada em "Quem chama".

| Função | Quem chama | Parâmetros | Efeito | Eventos emitidos |
| --- | --- | --- | --- | --- |
| `createOffer(borrower, amount, rateCDI, term, validityWindow)` | Ofertante cadastrado | Tomador cadastrado e diferente do ofertante; valores maiores que zero; limite do tomador maior ou igual a `amount` | Cria a oferta com status Ofertada e devolve o `offerId` | `OfferCreated` |
| `acceptOffer(offerId)` | Tomador da oferta | Oferta Ofertada e dentro da validade; os dois bancos ainda cadastrados; limite suficiente; `approve` do ofertante | Liquida na mesma transação: reduz o limite do tomador, transfere o BRLt do ofertante para o tomador e emite o NFT para o ofertante | `OfferAccepted`, `Transfer` (BRLt), `Transfer` (NFT), `OfferSettled` |
| `rejectOffer(offerId)` | Tomador da oferta | Oferta Ofertada e dentro da validade | Status vira Rejeitada | `OfferRejected` |
| `cancelOffer(offerId)` | Ofertante | Oferta Ofertada e dentro da validade | Status vira Cancelada | `OfferCancelled` |
| `expireOffer(offerId)` | Qualquer conta | Oferta Ofertada e `agora >= expiresAt` | Grava o status Expirada on-chain | `OfferExpired` |
| `registerInstitution(wallet)` | Admin | Endereço diferente de zero | Autoriza a carteira a operar | `InstitutionRegistered` |
| `revokeInstitution(wallet)` | Admin | — | Remove a autorização; ofertas abertas com ela deixam de poder ser aceitas | `InstitutionRevoked` |
| `setCreditLimit(institution, newLimit)` | Admin | Instituição cadastrada | Define o limite disponível (substitui o valor anterior) | `CreditLimitUpdated` |

## 5. Funções de leitura

Não custam gas e não precisam de carteira.

| Função | Retorno | Observação |
| --- | --- | --- |
| `getOffer(offerId)` | Struct `Offer` completa | Reverte com `OfferNotFound` se o id não existir. O `status` é o último gravado: uma oferta vencida continua aparecendo como Ofertada até alguém chamar `expireOffer` |
| `getOfferStatus(offerId)` | `uint8` do estado | Já devolve Expirada (4) quando a validade passou, mesmo sem `expireOffer`. **Use esta para exibir o status** |
| `availableLimit(institution)` | Limite disponível em centavos | Diminui a cada liquidação |
| `isRegisteredInstitution(account)` | `bool` | Útil para habilitar ou não as ações na tela |
| `BRLToken.balanceOf(account)` | Saldo em centavos | |
| `BRLToken.allowance(ofertante, CreditInterbankOffer)` | Valor autorizado | Para saber se ainda falta o `approve` |
| `CDIPositionToken.ownerOf(offerId)` | Dono do NFT da operação | Reverte se a oferta ainda não foi liquidada |

Struct `Offer`, na ordem em que os campos chegam:
`id`, `lender`, `borrower`, `amount`, `rateCDI`, `term`, `status`, `createdAt`,
`settledAt`, `expiresAt`.

Valores do `status`:

| Valor | Estado | Final? |
| --- | --- | --- |
| 0 | Ofertada (`Offered`) | Não |
| 1 | Aceita (`Accepted`) | Nunca fica gravado; aceite e liquidação ocorrem na mesma transação |
| 2 | Liquidada (`Settled`) | Sim |
| 3 | Cancelada (`Cancelled`) | Sim |
| 4 | Expirada (`Expired`) | Sim |
| 5 | Rejeitada (`Rejected`) | Sim |

## 6. Eventos a observar

O listener do backend só precisa escutar o `CreditInterbankOffer`, a partir do
bloco `11852299`. Campos marcados com `indexed` podem ser usados como filtro na
consulta de logs. O hash da transação, o número do bloco e o `logIndex` vêm do
próprio log.

| Evento | Campos (`indexed` em negrito) | O que o backend faz |
| --- | --- | --- |
| `OfferCreated` | **offerId**, **lender**, **borrower**, amount, rateCDI, term, expiresAt | Cria a oferta com status Ofertada. O `createdAt` é o horário do bloco |
| `OfferAccepted` | **offerId**, **borrower**, timestamp | Registra o aceite no histórico |
| `OfferSettled` | **offerId**, **lender**, **borrower**, amount, rateCDI, term, positionTokenId, timestamp | Muda para Liquidada; grava `settledAt`, o id do NFT e o hash da transação; reduz o limite do tomador |
| `OfferRejected` | **offerId**, **borrower**, timestamp | Muda para Rejeitada |
| `OfferCancelled` | **offerId**, timestamp | Muda para Cancelada |
| `OfferExpired` | **offerId**, timestamp | Muda para Expirada |
| `InstitutionRegistered` | **wallet**, timestamp | Marca a carteira como autorizada |
| `InstitutionRevoked` | **wallet**, timestamp | Marca a carteira como descadastrada |
| `CreditLimitUpdated` | **institution**, previousLimit, newLimit, timestamp | Atualiza o limite e guarda o histórico |

O `OfferSettled` traz sozinho os dados que o RNF03 pede (partes, valor, taxa e
horário), e o hash da transação vem do log.

### Três cuidados no listener

1. **Aceite e liquidação chegam juntos.** `OfferAccepted` e `OfferSettled` são
   emitidos na mesma transação. O estado final é sempre Liquidada.
2. **Falha não gera evento.** Se o aceite reverter (falta de limite, de saldo
   ou de `approve`), nenhum evento é emitido e a oferta continua Ofertada.
3. **Expiração pode não ter evento.** `OfferExpired` só aparece se alguém
   chamar `expireOffer`. Trate como Expirada toda oferta Ofertada com
   `expiresAt` no passado, ou use `getOfferStatus`.

Para não gravar o mesmo evento duas vezes, use `(transactionHash, logIndex)`
como chave única, e guarde o último bloco processado para retomar depois de
uma queda.

## 7. Erros e mensagens sugeridas

Quando uma transação reverte, o erro vem com nome e parâmetros, decodificáveis
pela ABI. Vale simular a chamada antes de enviar (`eth_call` ou
`simulateContract` no viem) para mostrar o erro sem gastar gas.

| Erro | Quando acontece | Mensagem sugerida |
| --- | --- | --- |
| `NotRegisteredInstitution(account)` | Carteira não cadastrada opera ou recebe oferta | Instituição não autorizada |
| `InsufficientLimit(borrower, requested, available)` | Tomador sem limite para o valor | Limite insuficiente para esta operação |
| `InvalidOfferParameters(amount, rateCDI, term)` | Valor, taxa ou prazo igual a zero | Valor, taxa e prazo precisam ser maiores que zero |
| `InvalidValidityWindow(validityWindow)` | Validade igual a zero | Informe a validade da oferta |
| `InvalidCounterparty(lender, borrower)` | Tomador igual ao ofertante ou endereço zero | Escolha outra instituição como tomadora |
| `NotEligibleBorrower(offerId, caller)` | Quem aceita ou rejeita não é o tomador | Só o banco tomador pode responder a esta oferta |
| `NotOfferOwner(offerId, caller)` | Quem cancela não é o ofertante | Só o banco ofertante pode cancelar |
| `InvalidOfferStatus(offerId, current, expected)` | Ação em oferta que não está Ofertada | Esta oferta já foi encerrada |
| `OfferHasExpired(offerId, expiresAt)` | Aceite, rejeição ou cancelamento após o vencimento | A validade desta oferta terminou |
| `OfferNotYetExpired(offerId, expiresAt)` | `expireOffer` antes do vencimento | A oferta ainda está no prazo |
| `OfferNotFound(offerId)` | Id inexistente | Oferta não encontrada |
| `ERC20InsufficientAllowance` / `ERC20InsufficientBalance` | Ofertante sem `approve` ou sem saldo de BRLt no aceite | O banco ofertante não tem saldo ou autorização suficiente |
| `ReentrancyGuardReentrantCall` | Tentativa de reentrância durante a liquidação | Operação recusada por segurança |

## 8. Exemplo: uma operação completa

Com o Foundry (`cast`), no terminal. Os mesmos passos valem para ethers ou viem,
trocando `cast send` por uma chamada de escrita e `cast call` por uma leitura.

```bash
OFFER=0x2401d88D300dD2CEdB83337bba9Ba29E7269079A
BRL=0x9591db5fa1345Cc12e7b8F747a3DdAeecc83d25D
BANCO_B=<endereço do tomador>

# Banco A autoriza R$ 1 mi e oferta para o banco B (100% do CDI, overnight, validade de 1 hora)
cast send $BRL "approve(address,uint256)" $OFFER 100000000 --rpc-url sepolia --account bancoA
cast send $OFFER "createOffer(address,uint256,uint256,uint256,uint256)" $BANCO_B 100000000 10000 1 3600 --rpc-url sepolia --account bancoA

# Banco B aceita a oferta 1: a liquidação DvP acontece nesta transação
cast send $OFFER "acceptOffer(uint256)" 1 --rpc-url sepolia --account bancoB

# Conferência
cast call $OFFER "getOfferStatus(uint256)(uint8)" 1 --rpc-url sepolia   # 2 = Liquidada
```

Uma operação assim já foi feita na Sepolia, com o id 1. As transações estão no
README principal, na seção "Demonstração on-chain".

## 9. O que fica fora do contrato

Estes pontos são responsabilidade do backend e do frontend:

- **Filtro de limite na tela:** listar como possíveis tomadores só as
  instituições com `availableLimit` maior ou igual ao valor. O contrato também
  recusa, mas a tela evita a tentativa.
- **Ocultar ofertas encerradas:** na Sepolia, qualquer pessoa lê os eventos. A
  ocultação depois do aceite é feita só na aplicação.
- **Comprovante para registro na Selic:** gerado pelo backend a partir dos
  dados do `OfferSettled` e do hash da transação.
- **Recomposição do limite:** sem o pagamento D+1, o limite consumido não volta
  sozinho. O admin recompõe com `setCreditLimit`.
