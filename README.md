# Aegis Wallet

Aegis Wallet is a security-first ERC-4337 smart wallet platform. This repository
is being built incrementally: this slice establishes the pinned contract toolchain,
an owner-controlled smart account, deterministic deployment, policy modules, a
local EntryPoint v0.8 UserOperation flow, a TypeScript AA client, and a responsive
frontend shell.

> **Status:** local contract and TypeScript checks pass. Sepolia deployment, a
> live provider-backed submission flow, and external security review are not
> claimed complete.

## Current implementation

- `AegisAccount.sol`
  - ERC-4337 v0.8 `BaseAccount` implementation.
  - EOA or ERC-1271-compatible owner signature validation through OpenZeppelin
    `SignatureChecker`.
  - EntryPoint-only execution and atomic batch execution.
  - Constructor-only initialization; no re-initialization path.
  - Owner changes require an account self-call, which must itself be initiated by
    a validated UserOperation.
- `AegisFactory.sol`
  - CREATE2 deterministic deployment.
  - Counterfactual address prediction.
  - EntryPoint v0.8 `SenderCreator` restriction to prevent init-code front-running.
  - Idempotent duplicate deployment behavior.
- Tests
  - Owner signature success/failure and modified-hash rejection.
  - EntryPoint and direct-execution authorization boundaries.
  - Self-call-only owner changes.
  - Atomic batch rollback.
  - Deterministic factory addresses and duplicate deployment.
  - Counterfactual deployment plus an end-to-end local UserOperation.
- `AegisPaymaster.sol`
  - EntryPoint v0.8 paymaster implementation with approved accounts, targets, and
    selectors.
  - Sponsor-signed, bounded policies with reservation accounting and restricted
    EntryPoint deposit/stake withdrawals.
- Authorization modules
  - `SessionKeyValidator.sol` enforces expiry, revocation, target/selector policy,
    per-transaction value, cumulative spending, and batch inspection.
  - `RecoveryModule.sol` enforces guardian threshold, delay, duplicate-approval
    prevention, cancellation, and explicit recovery events.
- `packages/aa-client`
  - viem `2.44.4` and permissionless `0.5.2` compatibility boundary, packed
    UserOperation builder, v0.8 EIP-712 signing, bundler submission, and receipt polling.
- `apps/web`
  - Responsive dark Aegis dashboard with live RPC reads when configured, explicit
    empty/error states, network configuration, and security-oriented review screens.
- `services/indexer`
  - Optional PostgreSQL read model for Aegis and EntryPoint events. It is not an
    authorization, balance, or transaction-validity source of truth.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the component diagram and
the selected ERC-4337 compatibility boundary. The initial implementation uses
EntryPoint v0.8.0 with Solidity 0.8.28. The frontend integration will use viem
and permissionless.js with an explicit EntryPoint version rather than relying on
SDK defaults.

## Repository layout

```text
contracts/
  src/
    AegisAccount.sol
    AegisFactory.sol
  test/
    unit/
    integration/
  foundry.toml
  remappings.txt
docs/
  ARCHITECTURE.md
  THREAT_MODEL.md
  DEPLOYMENT.md
.github/workflows/ci.yml
```

The optional PostgreSQL indexer and Sepolia deployment records remain follow-up
work. The web app intentionally keeps submission controls disabled until a real
bundler and verified contract addresses are configured.

## Prerequisites

- Foundry with a `forge` version that supports Solidity 0.8.28 and Cancun.
- Git.
- Node.js 20+ for the future web and TypeScript packages.

This environment currently has Node.js `v24.18.0`. Foundry is not installed on the
host, so the contract checks in this workspace are run reproducibly through the
pinned Foundry Docker image.

## Contract setup

From the repository root:

```bash
cd contracts
forge install --no-git eth-infinitism/account-abstraction@v0.8.0
forge install --no-git OpenZeppelin/openzeppelin-contracts@v5.4.0
forge install --no-git foundry-rs/forge-std@v1.9.7
forge build
forge test -vvv
```

From the repository root, the web checks are:

```bash
npm ci
npm run typecheck
npm run build:web
```

The dependency directories are intentionally ignored because they are reproducible
from these pinned references. The source imports are fixed through
`contracts/remappings.txt`.

## Local ERC-4337 flow

The integration test deploys a fresh EntryPoint v0.8 instance and factory, funds
the predicted account address before deployment, signs a packed UserOperation with
the owner key, deploys the account through EntryPoint's `SenderCreator`, and
executes a receiver call. To inspect the flow locally once Foundry is installed:

```bash
cd contracts
forge test --match-path test/integration/AegisUserOperation.t.sol -vvvv
```

## Security posture

Automated tests are not an audit. The project currently has no external audit and
does not claim production security. See [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md)
for the current trust assumptions and explicitly deferred review areas.

## Roadmap

1. Connect the frontend send/batch flows to a deployed account and bundler receipt lifecycle.
2. Add ERC-20 balance/transfer helpers and richer transaction-history indexing.
3. Run Slither and dependency review in CI, then address findings with documented severity.
4. Deploy and verify the contracts on Sepolia with separate deployer, owner, guardian,
   sponsor, and beneficiary accounts.
5. Run a provider-backed, separate-account end-to-end test and publish deployment records.
