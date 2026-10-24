import { Pool } from "pg";
import { createPublicClient, http, parseAbi, type Address, type Hex } from "viem";
import { sepolia } from "viem/chains";

const rpcUrl = process.env.SEPOLIA_RPC_URL;
const databaseUrl = process.env.DATABASE_URL;

if (!rpcUrl || !databaseUrl) {
  throw new Error("SEPOLIA_RPC_URL and DATABASE_URL are required to run the indexer");
}

const factoryAddress = process.env.AEGIS_FACTORY_ADDRESS as Address | undefined;
const entryPointAddress = process.env.ENTRY_POINT_ADDRESS as Address | undefined;
if (!factoryAddress || !entryPointAddress) {
  throw new Error("AEGIS_FACTORY_ADDRESS and ENTRY_POINT_ADDRESS are required");
}
const configuredFactoryAddress: Address = factoryAddress;
const configuredEntryPointAddress: Address = entryPointAddress;

const pool = new Pool({ connectionString: databaseUrl });
const client = createPublicClient({ chain: sepolia, transport: http(rpcUrl) });
const aegisEvents = parseAbi([
  "event AccountInitialized(address indexed entryPoint, address indexed owner)",
  "event AccountCreated(address indexed account, address indexed owner, uint256 indexed salt)",
  "event Executed(address indexed target, uint256 value, bytes4 indexed selector)",
  "event BatchExecuted(uint256 indexed callCount)",
  "event OwnerChanged(address indexed previousOwner, address indexed newOwner)",
  "event SessionKeyConfigured(address indexed sessionKey, uint48 expiresAt, uint256 maxValuePerTransaction, uint256 spendingLimit)",
  "event SessionKeyRevoked(address indexed sessionKey)",
  "event RecoveryProposed(bytes32 indexed proposalId, address indexed proposer, address indexed newOwner)",
  "event RecoveryFinalized(bytes32 indexed proposalId, address indexed previousOwner, address indexed newOwner)",
  "event SponsorshipReserved(bytes32 indexed userOpHash, address indexed account, uint256 maxCost)",
  "event SponsorshipSettled(bytes32 indexed userOpHash, address indexed account, uint256 actualCost)",
]);

async function migrate() {
  await pool.query(`
    create table if not exists aegis_events (
      id bigserial primary key,
      block_number bigint not null,
      block_hash text not null,
      transaction_hash text not null,
      log_index integer not null,
      contract_address text not null,
      event_name text not null,
      args jsonb not null,
      created_at timestamptz not null default now(),
      unique (transaction_hash, log_index)
    )
  `);
}

async function indexRange(fromBlock: bigint, toBlock: bigint) {
  const logs = await client.getLogs({
    address: [configuredFactoryAddress, configuredEntryPointAddress],
    events: aegisEvents,
    fromBlock,
    toBlock,
  });

  for (const log of logs) {
    await pool.query(
      `insert into aegis_events
        (block_number, block_hash, transaction_hash, log_index, contract_address, event_name, args)
       values ($1, $2, $3, $4, $5, $6, $7)
       on conflict (transaction_hash, log_index) do nothing`,
      [
        Number(log.blockNumber),
        log.blockHash ?? "0x",
        log.transactionHash ?? "0x",
        Number(log.logIndex ?? 0),
        log.address,
        log.eventName ?? "unknown",
        JSON.stringify(log.args ?? {}),
      ],
    );
  }
}

async function main() {
  await migrate();
  let cursor = BigInt(process.env.INDEXER_FROM_BLOCK ?? "0");
  for (;;) {
    const latest = await client.getBlockNumber();
    if (cursor <= latest) {
      const end = cursor + 1_000n < latest ? cursor + 1_000n : latest;
      await indexRange(cursor, end);
      cursor = end + 1n;
      continue;
    }
    await new Promise((resolve) => setTimeout(resolve, 5_000));
  }
}

void main().catch(async (error) => {
  console.error(error);
  await pool.end();
  process.exitCode = 1;
});
