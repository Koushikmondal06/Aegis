// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { IPaymaster } from "@account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";
import { AegisPaymaster } from "../../src/AegisPaymaster.sol";

contract AegisPaymasterTest is Test {
    uint256 internal constant SPONSOR_KEY = 0xC0FFEE;

    EntryPoint internal entryPoint;
    AegisPaymaster internal paymaster;
    TestTarget internal target;
    address internal sponsor;
    address internal account;

    function setUp() public {
        entryPoint = new EntryPoint();
        sponsor = vm.addr(SPONSOR_KEY);
        account = address(0xCAFE);
        paymaster = new AegisPaymaster(entryPoint, address(this), sponsor, 100);
        target = new TestTarget();

        paymaster.setApprovedAccount(account, true);
        paymaster.setApprovedTarget(address(target), true);
        paymaster.setApprovedSelector(address(target), TestTarget.increment.selector, true);
    }

    function test_ValidSponsorshipReservesAndSettlesBudget() public {
        PackedUserOperation memory userOp = _userOp(0, 80, address(target));
        bytes32 userOpHash = keccak256("entrypoint-hash");
        userOp.paymasterAndData = _paymasterData(userOp, 80, uint48(block.timestamp + 1 days), 0);

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            paymaster.validatePaymasterUserOp(userOp, userOpHash, 50);

        assertEq(uint48(validationData >> 160), uint48(block.timestamp + 1 days));
        assertEq(paymaster.reserved(), 80);

        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 31, 1);

        assertEq(paymaster.reserved(), 0);
        assertEq(paymaster.spent(), 31);
    }

    function test_RevertWhenSponsorshipSignatureDoesNotMatchUserOperation() public {
        PackedUserOperation memory userOp = _userOp(0, 80, address(target));
        userOp.paymasterAndData = _paymasterData(userOp, 80, uint48(block.timestamp + 1 days), 0);
        userOp.nonce = 1;

        vm.expectRevert(AegisPaymaster.InvalidSponsorshipSignature.selector);
        vm.prank(address(entryPoint));
        paymaster.validatePaymasterUserOp(userOp, keccak256("entrypoint-hash"), 50);
    }

    function test_RevertWhenBudgetIsReservedByAnotherOperation() public {
        PackedUserOperation memory first = _userOp(0, 80, address(target));
        first.paymasterAndData = _paymasterData(first, 80, uint48(block.timestamp + 1 days), 0);

        vm.prank(address(entryPoint));
        paymaster.validatePaymasterUserOp(first, keccak256("first"), 50);

        PackedUserOperation memory second = _userOp(1, 80, address(target));
        second.paymasterAndData = _paymasterData(second, 80, uint48(block.timestamp + 1 days), 0);

        vm.expectRevert(AegisPaymaster.SponsorshipBudgetExceeded.selector);
        vm.prank(address(entryPoint));
        paymaster.validatePaymasterUserOp(second, keccak256("second"), 50);
    }

    function test_RevertWhenCallerIsNotEntryPoint() public {
        PackedUserOperation memory userOp = _userOp(0, 80, address(target));
        userOp.paymasterAndData = _paymasterData(userOp, 80, uint48(block.timestamp + 1 days), 0);

        vm.expectRevert(AegisPaymaster.OnlyEntryPoint.selector);
        paymaster.validatePaymasterUserOp(userOp, keccak256("hash"), 50);
    }

    function _userOp(uint256 nonce, uint256, address destination)
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        userOp.sender = account;
        userOp.nonce = nonce;
        userOp.callData = abi.encodeCall(
            AegisAccount.execute, (destination, 0, abi.encodeCall(TestTarget.increment, (1)))
        );
    }

    function _paymasterData(
        PackedUserOperation memory userOp,
        uint256 maxCost,
        uint48 validUntil,
        uint48 validAfter
    ) internal returns (bytes memory) {
        bytes32 digest = paymaster.getSponsorshipDigest(
            userOp, address(target), TestTarget.increment.selector, maxCost, validUntil, validAfter
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SPONSOR_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory policy = abi.encode(validUntil, validAfter, maxCost, signature);
        return abi.encodePacked(
            address(paymaster), bytes16(uint128(100_000)), bytes16(uint128(100_000)), policy
        );
    }
}

contract TestTarget {
    uint256 public total;

    function increment(uint256 amount) external {
        total += amount;
    }
}
