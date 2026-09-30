# Liquefied Presale

Liquefied is liquid staking for AERO on Base. In its presale, you deposit AERO before launch and receive pLAERO, a receipt you later claim 1:1 for LAERO, Liquefied's token.

This repository holds the source of the two presale contracts, so you can check it against what is deployed. How the presale works is in the [presale docs](https://liquefied.finance/docs/presale-overview).

## Contracts

| Contract | Address | Source |
|---|---|---|
| Presale | [`0x8833E46D6f1a16Fba977bcf3924D05B681b078e3`](https://basescan.org/address/0x8833E46D6f1a16Fba977bcf3924D05B681b078e3#code) | [`src/presale/Presale.sol`](src/presale/Presale.sol) |
| pLAERO | [`0xB6e00Bbf26CE6B60bee1865e9df88bbC07e3e2Ea`](https://basescan.org/address/0xB6e00Bbf26CE6B60bee1865e9df88bbC07e3e2Ea#code) | [`src/presale/PresaleLAERO.sol`](src/presale/PresaleLAERO.sol) |

Basescan shows both as verified with an Exact Match: this source, comments included, compiles to the deployed bytecode.

### Presale

- It takes AERO from 1 Oct 2026 00:00 UTC until 22 Oct 2026 00:00 UTC, up to 200,000 AERO. These terms are fixed at deployment.
- 100 AERO buys 109 pLAERO: a 9% bonus.
- With a referral from another address, 100 AERO buys 110 pLAERO.
- Referrer payouts are calculated offchain from the `Deposited` events. No contract guarantees them.
- To deposit, approve the Presale to spend your AERO, then call `deposit`. AERO sent by a plain transfer mints no pLAERO.
- Each deposit goes straight from the buyer to the Liquefied Safe, the protocol's multisig. The Presale never holds deposits.
- A deposit larger than what is left under the cap reverts. It never fills in part.
- Deposits can't be withdrawn.
- The presale closes at 22 Oct 2026 00:00 UTC, when the cap fills, or when the owner ends it early. Once closed, it can't reopen.
- The owner is the Liquefied Safe. It can only end the presale early and recover tokens sent to the contract by mistake.
- Ownership moves only when a new owner accepts it. It can't be given up.

### pLAERO

- pLAERO (Presale Liquefied AERO) is an ERC-20 that transfers like any other.
- Only the Presale can mint it, and that can't change.
- It has no owner.
- Only a holder, or an address the holder approves, can burn it.
- Once the presale has closed and the Liquefied Safe has funded PresaleClaim, pLAERO is claimable 1:1 for LAERO. No contract forces that funding or sets its date: see [Presale trust and risks](https://liquefied.finance/docs/presale-trust).
- PresaleClaim is a separate contract deployed later. It isn't in this repository. Its terms, including the claim deadline, are in the [claim docs](https://liquefied.finance/docs/presale-claim).

## Check it yourself

The Presale was deployed with CREATE2. Its address depends only on the factory, the salt and the creation code: the compiled contract followed by its constructor arguments. If this source rebuilds that address, the deployed Presale is this code.

| | |
|---|---|
| Chain | Base (chain ID 8453) |
| Deployed | 30 Sep 2026 11:34:51 UTC, block 51,989,372 |
| Transaction | [`0x82be4c64…6e24`](https://basescan.org/tx/0x82be4c64579a72474ac3b3946e3745a6ae72bb2ff5abc49538377092096b6e24) |
| Factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` (the standard CREATE2 factory) |
| Salt | `keccak256("liquefied.presale")` |

The Presale's constructor arguments:

| Argument | Value |
|---|---|
| `_paymentToken` | AERO `0x940181a94A35A4569E4529A3CDfB74e38FD98631` |
| `_treasury` | Liquefied Safe `0x049DE430D3f1915799B07807040af3F5F5Bc4628` |
| `_owner` | Liquefied Safe `0x049DE430D3f1915799B07807040af3F5F5Bc4628` |
| `_cap` | `200000000000000000000000` (200,000 AERO) |
| `_bonusBps` | `900` (9%) |
| `_presaleStart` | `1790812800` (1 Oct 2026 00:00 UTC) |
| `_presaleEnd` | `1792627200` (22 Oct 2026 00:00 UTC) |
| `_receiptName` | `Presale Liquefied AERO` |
| `_receiptSymbol` | `pLAERO` |

### 1. Build

With [Foundry](https://getfoundry.sh):

```sh
git clone --recurse-submodules https://github.com/liquefiedfi/Presale.git
cd Presale
forge build
```

`foundry.toml` pins the build settings: optimizer on (200 runs), EVM version Cancun, no via-IR. The contracts' exact `pragma` fixes solc 0.8.35. Together they reproduce the deployed bytecode. OpenZeppelin Contracts v5.6.1 (commit `5fd1781b`) is a submodule. `forge build` prints some compiler and lint warnings. They are expected and don't change the bytecode.

### 2. Rebuild the Presale's address

```sh
ARGS=$(cast abi-encode "constructor(address,address,address,uint128,uint16,uint64,uint64,string,string)" \
  0x940181a94A35A4569E4529A3CDfB74e38FD98631 \
  0x049DE430D3f1915799B07807040af3F5F5Bc4628 \
  0x049DE430D3f1915799B07807040af3F5F5Bc4628 \
  200000000000000000000000 900 1790812800 1792627200 \
  "Presale Liquefied AERO" "pLAERO")
INIT=$(forge inspect Presale bytecode)${ARGS#0x}

cast create2 --deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C \
  --salt $(cast keccak liquefied.presale) --init-code-hash $(cast keccak $INIT)
# 0x8833E46D6f1a16Fba977bcf3924D05B681b078e3
```

### 3. Check pLAERO

pLAERO's creation code is part of the Presale's, so step 2 covers its code too. The Presale created it first, at nonce 1, since a contract's nonce starts at 1:

```sh
cast compute-address 0x8833E46D6f1a16Fba977bcf3924D05B681b078e3 --nonce 1
# Computed Address: 0xB6e00Bbf26CE6B60bee1865e9df88bbC07e3e2Ea
```

### 4. Check the deploy transaction

The transaction sent the salt followed by `$INIT` to the factory. This prints `match` if its input is exactly that:

```sh
IN=$(cast tx 0x82be4c64579a72474ac3b3946e3745a6ae72bb2ff5abc49538377092096b6e24 input --rpc-url https://mainnet.base.org)
[ "$IN" = "$(cast keccak liquefied.presale)${INIT#0x}" ] && echo match
# match
```

## Links

- Presale docs: [liquefied.finance/docs/presale-overview](https://liquefied.finance/docs/presale-overview)
- Risks: [liquefied.finance/docs/presale-trust](https://liquefied.finance/docs/presale-trust)
- Disclaimer: [liquefied.finance/docs/disclaimer](https://liquefied.finance/docs/disclaimer)
- Contract addresses: [liquefied.finance/docs/contract-addresses](https://liquefied.finance/docs/contract-addresses)
- X: [@LiquefiedFi](https://x.com/LiquefiedFi)

Only trust links from liquefied.finance and @LiquefiedFi.

## License

MIT. See [LICENSE](LICENSE).
