# Aegis Wallet Progress

**Checkpoint date:** October 24, 2026
**Branch:** `main`
**Project status:** Local implementation complete for the current foundation; Sepolia release work remains.

## Summary

Aegis Wallet has moved from an empty repository to a tested ERC-4337 v0.8
foundation with smart-account contracts, deterministic deployment, policy modules,
local UserOperation execution, a TypeScript AA client, a responsive frontend shell,
an optional PostgreSQL indexer, CI configuration, and security documentation.

This checkpoint does **not** claim that Aegis is audited, production-secure, or
deployed to Sepolia.

## Progress by phase

| Phase | Status | Notes |
| --- | --- | --- |
| Repository audit and setup | Complete | Repository structure, tooling, environment files, CI, and documentation were added. |
| ERC-4337 version selection | Complete | Pinned to account-abstraction `v0.8.0`, Solidity `0.8.28`, EntryPoint v0.8 semantics. |
| Core smart account | Complete for local milestone | Owner validation, EntryPoint gate, ETH/ERC-20 execution, atomic batches, and owner self-call changes are implemented. |
| Deterministic factory | Complete for local milestone | CREATE2 prediction, SenderCreator restriction, duplicate deployment, and counterfactual deployment are tested. |
| ERC-4337 local lifecycle | Complete for local milestone | Counterfactual deployment, UserOperation signing, EntryPoint handling, execution, and receipt-producing flow are covered by integration tests. |
| Policy paymaster | Complete for local milestone | Allowlists, sponsor signatures, validity windows, budget reservations, settlement, and restricted withdrawals are implemented and tested. |
| Session keys | Complete for local milestone | Expiry, revocation, target/selector permissions, per-operation limits, cumulative limits, and batch inspection are implemented and tested. |
| Guardian recovery | Complete for local milestone | Threshold, delay, duplicate approval prevention, cancellation, finalization, and events are implemented and tested. |
| Frontend | Foundation complete | Dashboard, account preview, live RPC reads, network configuration, security views, and explicit empty/error states are present. |
| AA client package | Foundation complete | viem `2.44.4` and permissionless `0.5.2` are pinned; UserOperation building, v0.8 typed-data signing, submission, and receipt polling are available. |
| Indexer | Foundation complete | PostgreSQL event read-model scaffold is present; it is not an authorization or balance source of truth. |
| Security automation | Partial | Foundry unit, integration, fuzz, and invariant tests run. Slither is not installed in the current environment. |
| Sepolia deployment | Not started | No live addresses, transaction hashes, provider credentials, or verification claims have been added. |

## Implemented contract files

- `contracts/src/AegisAccount.sol`
- `contracts/src/AegisFactory.sol`
- `contracts/src/AegisPaymaster.sol`
- `contracts/src/SessionKeyValidator.sol`
- `contracts/src/RecoveryModule.sol`
- `contracts/script/Deploy.s.sol`

## Test coverage checkpoint

The latest Foundry run completed successfully:

- **29 tests passed**
- **0 tests failed**
- Counterfactual UserOperation integration passed
- ETH and ERC-20 execution passed
- Owner EOA and ERC-1271 signature validation passed
- Factory fuzz test passed with 256 runs
- Invariant tests passed with 128,000 calls per invariant
- Paymaster budget, signature, allowlist, and settlement tests passed
- Session-key and guardian recovery boundary tests passed

The command used was:

```bash
docker run --rm --entrypoint forge \
  -v "$PWD:/workspace" \
  -w /workspace/contracts \
  ghcr.io/foundry-rs/foundry:stable test -vv
```

## TypeScript and frontend checks

The following checks also pass:

```bash
npm ci
npm run typecheck
npm run build:web
```

The frontend development server can be started with:

```bash
npm run dev:web
```

The local preview URL is `http://localhost:5173`.

## Current limitations

1. The frontend send and batch screens are infrastructure-aware UI foundations,
   but they are not yet connected to a deployed Aegis factory, bundler, and live
   paymaster service.
2. No Sepolia deployment has been performed.
3. No external smart-contract audit has been performed.
4. Slither and dependency security review have not yet run in CI.
5. The indexer requires a configured PostgreSQL instance and deployed addresses.
6. ERC-20 balances and transfer helpers still need richer frontend integration.
7. Bundler replacement, reorg, finality, and provider outage behavior need a
   provider-backed end-to-end test.

## Next implementation steps

### Step 1 — Complete live AA integration

- Deploy the factory, account implementation, and paymaster to Sepolia.
- Configure a compatible EntryPoint v0.8 bundler.
- Wire the frontend send and batch builders to `AegisAaClient`.
- Display preparing, signing, submitted, included, succeeded, and reverted states
  from actual UserOperation receipts.

### Step 2 — Complete asset and activity views

- Add ERC-20 balance reads and safe transfer helpers.
- Add indexed UserOperation and protocol-event history.
- Add receipt links only after confirmed inclusion.

### Step 3 — Security automation

- Add Slither to CI.
- Review all findings and document severity and disposition.
- Add more stateful invariants around paymaster accounting, session-key spending,
  and recovery configuration changes.

### Step 4 — Sepolia release checklist

- Verify EntryPoint address and bytecode for Sepolia.
- Use separate deployer, owner, sponsor, guardian, and beneficiary accounts.
- Configure paymaster allowlists and deposit/stake policies.
- Verify contracts on the explorer.
- Run an end-to-end UserOperation with a separate test account.
- Record deployment addresses and transaction hashes in deployment documentation.

## Git checkpoint history

The repository started from a single initial commit. This progress document is the
first implementation checkpoint commit and should remain updated after each major
phase. Keep commits focused and use conventional commit messages, for example:

```text
docs: add project progress tracker
feat: connect live user operation flow
test: add paymaster invariants
deploy: publish sepolia contract addresses
```

Do not add private keys, API tokens, sponsor signatures, or private RPC URLs to
this file or to GitHub.
