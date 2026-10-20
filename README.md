# GoatPro (GPRO)

GoatPro is an immutable ERC-20 token. Its constructor mints the entire supply
once to `msg.sender`, the immediate deployer.

| Parameter | Value |
| --- | --- |
| Solidity artifact | `src/GoatPro.sol:GoatPro` |
| Token name | `GoatPro` |
| Symbol | `GPRO` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None; encoded arguments are empty |
| Constructor ETH value | `0` |
| Intended launch chain | Robinhood Chain, chain ID `4663`, per the assignment |

## Behavior and assumptions

The token uses the unmodified OpenZeppelin ERC-20 implementation pinned in
[DEPENDENCIES.md](DEPENDENCIES.md). There are no fees, burns, rebases, transfer
restrictions, ownership roles, additional minting entry points, upgrades, or
post-deployment settings. The `INITIAL_SUPPLY` constant is denominated in
smallest units. All balances and allowances use those units.

Transfers and approvals return `true` on success and revert with ERC-6093 custom
errors on invalid addresses, insufficient balance, or insufficient allowance.
Zero-value transfers between nonzero addresses and self-transfers are supported.
Transfers to the zero address are rejected, including zero-value transfers.
An approval replaces the previous allowance. `transferFrom` reduces a finite
allowance; a maximum `uint256` allowance remains unchanged.

Construction emits one `Transfer(address(0), deployer, 10^27)` event.
Transfers emit `Transfer`, and explicit approvals emit `Approval`.
This OpenZeppelin version does not emit an additional `Approval` event when
`transferFrom` spends an allowance; integrations should query `allowance`.

The token makes no external calls, invokes no recipient callbacks, and depends
on no oracle, chain-specific address, timestamp, block number, or off-chain
service. It needs neither an owner nor a keeper.

## Build and checks

Foundry and Solidity `0.8.26` must be installed. All Solidity dependencies are
vendored as ordinary files in `lib/`; no package download, submodule, RPC, keys,
environment-based test configuration, FFI, or filesystem permissions are needed.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x81354be4c972b97b961098c3b8979e3fd77a73d9342d06d83de1d23c1d0b7bda forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Paris EVM target, optimizer settings
(enabled, 200 runs), and `bytecode_hash = "none"`. Paris provides conservative
EVM compatibility without requiring newer opcodes. Keep these settings for
bytecode reproduction.

The tests cover metadata, direct and CREATE2 factory deployment, the mint event,
exact transfers, zero and full amounts, self-transfers, approvals and revocation,
finite and infinite allowances, unauthorized spending, failure atomicity, absent
administrative entry points, and prohibited runtime opcodes. Four fuzz tests
exercise amounts and recipients with 512 cases each. A stateful invariant checks
the fixed supply and conservation of balances through 128 sequences of up to 64
transfers, approvals, and delegated transfers.

The launch-flow test models exact factory/distributor/pool/holder token movements.
It does not deploy a real AMM or execute swaps. The supplied protected launch
harness depends on separate factory, PoolManager, and manifest infrastructure;
its full integration checks belong to the independent launch verifier.

## Deployment and operational responsibilities

The deployable contract is `GoatPro`; it has no linked libraries and needs no
initialization call. Build and inspect its ABI and creation bytecode locally:

```sh
forge inspect src/GoatPro.sol:GoatPro abi
forge inspect src/GoatPro.sol:GoatPro bytecode
```

For the IdentityMD launch, the factory creates the token and receives all
`10^27` units. The token does not use `tx.origin` or pre-allocate supply.
The factory handles the assignment's 10% distributor share, 80% pool share, and
10% requester remainder after construction. Pool settings, distribution,
economics, and the launch manifest are external to this token; there are no
application contracts in this project. A direct deployment instead gives all
tokens to the direct constructor caller.

The authorized launch operator is responsible for the manifest, factory
deployment, subsequent allocation, source verification, and checking the
deployed metadata, supply, and initial recipient. No deployment or broadcast
is performed by this repository.

After launch there is nothing to configure and no privileged operator.
Holders control transfers and approvals; an approved spender can spend within
its allowance. Integrations should use appropriate approval amounts and handle
the standard approval replacement race (revoke an existing allowance and wait
for confirmation before setting a replacement when necessary).

There is no recovery or rescue function. Tokens sent to an inaccessible address
or to the token contract itself cannot be recovered by an administrator.
Ordinary native-currency sends revert, and forcibly sent native currency is
also not recoverable.

The local review checks constructor-only minting, unchanged transfer accounting,
absence of privileged functions and external calls, allowance rollback on
failure, and conservation across transaction sequences. Foundry tests do not
replace independent security review. Slither/Mythril and live-chain integration
checks are not part of this project's recorded local checks.
