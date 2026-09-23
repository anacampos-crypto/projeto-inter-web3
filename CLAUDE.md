# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Academic proof-of-concept for the Banco Inter interbank credit protocol
(overnight loans referencing CDI rate). Built with Foundry. This is a
Web3/Solidity-only repo — no frontend or backend code here.

The current deliverable (Semana 1, 14/09–20/09) is the offer state machine
interface and a minimal mock implementation; the real DvP settlement
contract and CDI token are Semana 2 work.

## Commands

```bash
forge build          # compile
forge test -vv       # run tests (expect all passing; -vv for revert traces)
forge test -vvvv --match-test <testName>   # run a single test with full traces
forge fmt            # format Solidity source
```

Dependencies are managed as git submodules under `lib/` (currently
`forge-std`). After cloning, run `git submodule update --init --recursive`
if `lib/forge-std` is empty.

## Architecture

- `src/interfaces/ICreditInterbankOffer.sol` is the source of truth for the
  protocol's data model (`Offer` struct, `OfferStatus` enum), events, and
  custom errors. Any implementation contract must conform to this interface.
- `docs/maquina-estados-oferta.md` documents the offer state machine
  (`Offered → Accepted → Settled`, or `Offered → Cancelled`) including the
  guard conditions and events for each transition. Read this before changing
  state-transition logic — it is the spec, not just documentation.
- `test/CreditInterbankOffer.t.sol` currently contains both the test suite
  *and* `CreditInterbankOfferMock`, a temporary minimal implementation of
  `ICreditInterbankOffer` used only to exercise the interface. `acceptOffer`
  is intentionally unimplemented (reverts) in the mock — atomic DvP
  settlement (`Accepted → Settled` in the same transaction) is Semana 2
  scope. When the real contract lands in `src/`, this mock should be
  replaced rather than extended.
- Key invariant from the state machine: `Accepted` and `Settled` happen in
  the same transaction — if settlement fails, the whole transaction reverts
  and the offer stays `Offered` (there is no persisted "rejected" state).
  `Settled` and `Cancelled` are final states.
- All on-chain interaction is expected to target Sepolia testnet with
  simulated assets only (`sepolia` RPC/Etherscan config in `foundry.toml`,
  keys read from `.env` via `SEPOLIA_RPC_URL` / `ETHERSCAN_API_KEY`).
