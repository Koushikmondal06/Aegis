import {
  concatHex, createPublicClient, encodeFunctionData, http, padHex, toHex, type Account, type Address,
  type Chain, type Hex, type PublicClient, type Transport, type WalletClient,
} from "viem";
import { entryPoint08Abi, getUserOperationTypedData } from "viem/account-abstraction";
import { createSmartAccountClient } from "permissionless";

const factoryAbi = [
  {
    name: "getAddress",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "salt", type: "uint256" },
    ],
    outputs: [{ name: "account", type: "address" }],
  },
] as const;

const accountAbi = [
  {
    name: "execute",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "target", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
    outputs: [],
  },
] as const;

export type PackedUserOperation = {
  sender: Address;
  nonce: bigint;
  initCode: Hex;
  callData: Hex;
  accountGasLimits: Hex;
  preVerificationGas: bigint;
  gasFees: Hex;
  paymasterAndData: Hex;
  signature: Hex;
};

export type UserOperationReceipt = {
  userOpHash: Hex;
  sender: Address;
  nonce: Hex;
  actualGasCost: Hex;
  actualGasUsed: Hex;
  success: boolean;
  receipt: { transactionHash: Hex; blockNumber: Hex };
};

export type AegisAaClientConfig = {
  chain: Chain;
  publicClient: PublicClient<Transport, Chain>;
  walletClient: WalletClient<Transport, Chain>;
  entryPoint: Address;
  factory: Address;
  bundlerUrl: string;
};

function pack128(high: bigint, low: bigint): Hex {
  return concatHex([padHex(toHex(high), { size: 16 }), padHex(toHex(low), { size: 16 })]);
}

function toRpcUserOperation(userOp: PackedUserOperation) {
  return {
    sender: userOp.sender,
    nonce: toHex(userOp.nonce),
    initCode: userOp.initCode,
    callData: userOp.callData,
    accountGasLimits: userOp.accountGasLimits,
    preVerificationGas: toHex(userOp.preVerificationGas),
    gasFees: userOp.gasFees,
    paymasterAndData: userOp.paymasterAndData,
    signature: userOp.signature,
  };
}

export class AegisAaClient {
  private readonly bundler: PublicClient<Transport, Chain>;

  constructor(private readonly config: AegisAaClientConfig) {
    this.bundler = createPublicClient({
      chain: config.chain,
      transport: http(config.bundlerUrl),
    });
  }

  async predictAccount(owner: Address, salt: bigint): Promise<Address> {
    return this.config.publicClient.readContract({
      address: this.config.factory,
      abi: factoryAbi,
      functionName: "getAddress",
      args: [owner, salt],
    });
  }

  async buildUserOperation(args: {
    owner: Address;
    salt: bigint;
    target: Address;
    value?: bigint;
    data?: Hex;
    paymasterAndData?: Hex;
  }): Promise<PackedUserOperation> {
    const sender = await this.predictAccount(args.owner, args.salt);
    const bytecode = await this.config.publicClient.getCode({ address: sender });
    const initCode = bytecode && bytecode !== "0x"
      ? "0x"
      : concatHex([
          this.config.factory,
          encodeFunctionData({
            abi: [
              {
                name: "createAccount",
                type: "function",
                stateMutability: "nonpayable",
                inputs: [
                  { name: "owner", type: "address" },
                  { name: "salt", type: "uint256" },
                ],
                outputs: [{ name: "account", type: "address" }],
              },
            ] as const,
            functionName: "createAccount",
            args: [args.owner, args.salt],
          }),
        ]);

    const nonce = await this.config.publicClient.readContract({
      address: this.config.entryPoint,
      abi: entryPoint08Abi,
      functionName: "getNonce",
      args: [sender, 0n],
    });
    const callData = encodeFunctionData({
      abi: accountAbi,
      functionName: "execute",
      args: [args.target, args.value ?? 0n, args.data ?? "0x"],
    });

    return {
      sender,
      nonce,
      initCode,
      callData,
      accountGasLimits: pack128(3_000_000n, 250_000n),
      preVerificationGas: 80_000n,
      gasFees: pack128(1_000_000_000n, 2_000_000_000n),
      paymasterAndData: args.paymasterAndData ?? "0x",
      signature: "0x",
    };
  }

  async signUserOperation(userOp: PackedUserOperation, account: Account): Promise<PackedUserOperation> {
    const typedData = getUserOperationTypedData({
      chainId: this.config.chain.id,
      entryPointAddress: this.config.entryPoint,
      userOperation: {
        sender: userOp.sender,
        nonce: userOp.nonce,
        callData: userOp.callData,
        callGasLimit: 250_000n,
        verificationGasLimit: 3_000_000n,
        preVerificationGas: userOp.preVerificationGas,
        maxFeePerGas: 2_000_000_000n,
        maxPriorityFeePerGas: 1_000_000_000n,
        signature: "0x",
      },
    });
    const signature = await this.config.walletClient.signTypedData({ account, ...typedData });

    return { ...userOp, signature };
  }

  createPermissionlessClient(config: Parameters<typeof createSmartAccountClient>[0]) {
    return createSmartAccountClient(config);
  }

  async sendUserOperation(userOp: PackedUserOperation): Promise<Hex> {
    return this.bundler.request({
      method: "eth_sendUserOperation" as never,
      params: [toRpcUserOperation(userOp), this.config.entryPoint] as never,
    });
  }

  async waitForReceipt(userOpHash: Hex, timeoutMs = 120_000): Promise<UserOperationReceipt> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const receipt = await this.bundler.request({
        method: "eth_getUserOperationReceipt" as never,
        params: [userOpHash] as never,
      });
      if (receipt) return receipt as UserOperationReceipt;
      await new Promise((resolve) => setTimeout(resolve, 2_000));
    }
    throw new Error("Timed out waiting for the UserOperation receipt");
  }
}
