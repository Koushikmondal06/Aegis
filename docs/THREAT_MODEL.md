# Aegis Wallet Threat Model

## Current assets

- Owner control of each Aegis account.
- Native ETH and ERC-20 assets held by an account.
- Account nonce and UserOperation authorization state.
- Deterministic account address and counterfactual funding.

## Current trust assumptions

- The configured EntryPoint contract is the intended audited deployment for the
  selected network and its address/code hash is verified before use.
- The owner signer protects its private key and signs the exact UserOperation hash.
- A bundler may censor or delay operations, but cannot authorize an operation that
  the account rejects.
- OpenZeppelin and the pinned account-abstraction dependency are reviewed as
  third-party dependencies before deployment.

## Threats addressed in the core slice

| Threat | Mitigation |
| --- | --- |
| Direct unauthorized account execution | `execute` and `executeBatch` require the configured EntryPoint. |
| Invalid or modified UserOperation signature | Owner signature is checked against the supplied EntryPoint UserOperation hash. |
| Re-initialization replacing the owner | Constructor-only initialization; the account has no initializer. |
| Factory init-code front-running | Factory creation is restricted to EntryPoint's `SenderCreator`. |
| Partial batch execution | The account reverts the entire batch on the first failed call. |
| Unauthorized owner replacement | `setOwner` requires a self-call from a validated account execution. |
| Counterfactual address mismatch | CREATE2 prediction is tested against the deployed address. |
| Session-key privilege escalation | Session authorization accepts only explicit `execute`/`executeBatch` calldata and checks every target, selector, per-call value, and cumulative value. |
| Expired or revoked session key | Expiry and revocation are checked during account validation. |
| Recovery approval replay | Proposals have unique IDs and each guardian can approve once. Finalization consumes the proposal. |
| Recovery delay bypass | Finalization checks both threshold and `block.timestamp >= executeAfter`. |
| Paymaster policy bypass | Account, target, selector, sponsor signature, validity window, and budget reservation are checked on-chain. |
| Unauthorized paymaster drain | Stake/deposit withdrawals are admin-only; validation and settlement are EntryPoint-only. |

## Deferred threats

- Guardian collusion, guardian churn, and operational loss of the configured threshold.
- Paymaster signer key compromise and sponsor budget exhaustion.
- ERC-20 tokens with non-standard return values or callback behavior in future transfer helpers.
- Bundler/RPC censorship, replacement, reorgs, and receipt finality policy.
- Frontend phishing, malicious browser extensions, and signer UX mistakes.
- Upgradeability and storage-layout risk. The initial account is intentionally non-upgradeable.

## Security process

Before any Sepolia or production-like deployment, the project must:

1. Run Foundry unit, integration, fuzz, and invariant tests.
2. Run Slither and dependency/source review.
3. Verify the EntryPoint address and bytecode hash for the target network.
4. Exercise failure paths with separate deployer, owner, guardian, and beneficiary accounts.
5. Document unresolved findings; passing tests must not be described as an audit.
