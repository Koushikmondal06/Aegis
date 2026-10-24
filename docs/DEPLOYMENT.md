# Deployment Notes

## Local contracts

The local integration tests deploy a fresh EntryPoint instance, factory, account,
and receiver. This keeps the first milestone independent from an external bundler
or paymaster and makes the UserOperation path reproducible in Anvil/Forge.

```bash
anvil
```

In a second terminal, after installing the pinned libraries:

```bash
cd contracts
forge build
forge test --match-path test/integration/AegisUserOperation.t.sol -vvvv
```

## Sepolia status

No Sepolia deployment has been performed yet. There are intentionally no contract
addresses, transaction hashes, API keys, or claims of verification in this repository.

Before deployment, the release checklist must capture:

- EntryPoint v0.8 address and deployed bytecode hash for Sepolia.
- Factory and account implementation deployment transactions.
- Deployer and owner separation.
- Bundler RPC compatibility with EntryPoint v0.8.
- Paymaster service compatibility, policy configuration, and deposit status.
- Explorer verification output and a separate-account end-to-end UserOperation receipt.

Once those values are verified, deploy the Aegis-owned contracts with:

```bash
cd contracts
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify \
  --etherscan-api-key "$ETHERSCAN_API_KEY"
```

The script deploys `AegisFactory` and `AegisPaymaster` only. It deliberately does
not deploy an EntryPoint replacement and does not configure allowlists, deposits,
stakes, or sponsor signing keys automatically. Those are separate reviewed steps.

## Environment variables

Use a private, uncommitted `.env` file based on the root `.env.example`:

```text
SEPOLIA_RPC_URL=
SEPOLIA_BUNDLER_RPC_URL=
SEPOLIA_PAYMASTER_RPC_URL=
DEPLOYER_PRIVATE_KEY=
ETHERSCAN_API_KEY=
```

Never put real values in source control, CI logs, screenshots, or documentation.
