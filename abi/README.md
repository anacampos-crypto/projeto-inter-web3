# ABIs dos contratos

ABIs versionadas para o backend e o frontend importarem. Cada arquivo é a ABI
completa do contrato (funções, eventos e erros), no formato JSON padrão aceito
por ethers, viem e web3.js.

| Arquivo | Contrato | Endereço na Sepolia |
| --- | --- | --- |
| `CreditInterbankOffer.json` | Ofertas, limites e liquidação DvP | `0x2401d88D300dD2CEdB83337bba9Ba29E7269079A` |
| `BRLToken.json` | Real tokenizado fictício (ERC-20, 2 casas decimais) | `0x9591db5fa1345Cc12e7b8F747a3DdAeecc83d25D` |
| `CDIPositionToken.json` | NFT de posição (ERC-721) | `0xae1C70253946E2a4Cf42c1C979ABD9E8d76AE3c7` |

Os endereços, o `chainId` (11155111) e o bloco inicial para ler eventos
(`startBlock`) também estão em `deployments/sepolia.json`.

## Como usar

**ethers v6**

```ts
import { Contract, JsonRpcProvider } from "ethers";
import offerAbi from "./abi/CreditInterbankOffer.json";
import deployment from "./deployments/sepolia.json";

const provider = new JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
const offers = new Contract(deployment.CreditInterbankOffer, offerAbi, provider);

const status = await offers.getOfferStatus(1n); // 2n = Liquidada
offers.on("OfferSettled", (offerId, lender, borrower, amount) => { /* ... */ });
```

**viem**

```ts
import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import offerAbi from "./abi/CreditInterbankOffer.json";

const client = createPublicClient({ chain: sepolia, transport: http(process.env.SEPOLIA_RPC_URL) });
const status = await client.readContract({
  address: "0x2401d88D300dD2CEdB83337bba9Ba29E7269079A",
  abi: offerAbi,
  functionName: "getOfferStatus",
  args: [1n],
});
```

## Versão

As ABIs correspondem ao código implantado na Sepolia e acompanham as tags de
release do repositório (por exemplo, `v1.0.0`). Para usar uma versão fixa,
importe os arquivos a partir da tag, não do `main`.

## Como regenerar

Sempre que um contrato em `src/` mudar, rode na raiz do projeto e commite os
arquivos alterados:

```bash
bash script/export-abi.sh
```

Se os contratos forem reimplantados, atualize também os endereços desta página e
o `deployments/<ambiente>.json`.
