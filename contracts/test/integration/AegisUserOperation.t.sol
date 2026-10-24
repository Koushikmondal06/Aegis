// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";
import { AegisFactory } from "../../src/AegisFactory.sol";

contract AegisUserOperationIntegrationTest is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;

    EntryPoint internal entryPoint;
    AegisFactory internal factory;
    address internal owner;
    TestReceiver internal receiver;

    function setUp() public {
        entryPoint = new EntryPoint();
        factory = new AegisFactory(entryPoint);
        owner = vm.addr(OWNER_KEY);
        receiver = new TestReceiver();
    }

    function test_CounterfactualAccountDeploysAndExecutesUserOperation() public {
        uint256 salt = 123;
        address sender = factory.getAddress(owner, salt);
        bytes memory initCode = abi.encodePacked(
            address(factory), abi.encodeCall(AegisFactory.createAccount, (owner, salt))
        );
        bytes memory callData = abi.encodeCall(
            AegisAccount.execute,
            (address(receiver), 0, abi.encodeCall(TestReceiver.increment, (11)))
        );

        // Counterfactual addresses can be funded before their code is deployed.
        vm.deal(sender, 1 ether);

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: sender,
            nonce: entryPoint.getNonce(sender, 0),
            initCode: initCode,
            callData: callData,
            accountGasLimits: _pack(3_000_000, 250_000),
            preVerificationGas: 50_000,
            gasFees: _pack(1, 1),
            paymasterAndData: "",
            signature: ""
        });
        userOp.signature = _sign(userOp, OWNER_KEY);

        entryPoint.handleOps(_asArray(userOp), payable(address(0xBEEF)));

        assertGt(sender.code.length, 0);
        assertEq(AegisAccount(payable(sender)).owner(), owner);
        assertEq(receiver.total(), 11);
    }

    function _sign(PackedUserOperation memory userOp, uint256 privateKey)
        internal
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, entryPoint.getUserOpHash(userOp));
        return abi.encodePacked(r, s, v);
    }

    function _pack(uint256 high, uint256 low) internal pure returns (bytes32) {
        return bytes32((high << 128) | low);
    }

    function _asArray(PackedUserOperation memory userOp)
        internal
        pure
        returns (PackedUserOperation[] memory userOps)
    {
        userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
    }
}

contract TestReceiver {
    uint256 internal _total;

    function increment(uint256 amount) external {
        _total += amount;
    }

    function total() external view returns (uint256) {
        return _total;
    }
}
