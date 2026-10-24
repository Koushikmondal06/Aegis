// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";
import { RecoveryModule } from "../../src/RecoveryModule.sol";
import { SessionKeyValidator } from "../../src/SessionKeyValidator.sol";

contract AuthorizationModulesTest is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;
    uint256 internal constant SESSION_KEY = 0xB0B;

    EntryPoint internal entryPoint;
    AegisAccount internal account;
    TestReceiver internal receiver;
    address internal owner;
    address internal sessionKey;

    function setUp() public {
        entryPoint = new EntryPoint();
        owner = vm.addr(OWNER_KEY);
        sessionKey = vm.addr(SESSION_KEY);
        account = new AegisAccount(entryPoint, owner);
        receiver = new TestReceiver();
    }

    function test_SessionKeyEnforcesTargetSelectorAndSpendingLimit() public {
        uint48 expiresAt = uint48(block.timestamp + 1 days);
        _configureSession(expiresAt, 10, 12);

        bytes memory callData = abi.encodeCall(
            AegisAccount.execute,
            (address(receiver), 5, abi.encodeCall(TestReceiver.increment, (1)))
        );
        PackedUserOperation memory userOp = _userOp(callData);
        bytes32 userOpHash = keccak256("session-operation");
        userOp.signature = abi.encode(sessionKey, _signature(userOpHash, SESSION_KEY));

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(uint48(validationData >> 160), expiresAt);
        (,,, uint256 spent,) = account.sessionKeys(sessionKey);
        assertEq(spent, 5);
    }

    function test_RevertWhenSessionKeyUsesDisallowedSelector() public {
        _configureSession(uint48(block.timestamp + 1 days), 10, 100);
        bytes memory callData = abi.encodeCall(
            AegisAccount.execute,
            (address(receiver), 0, abi.encodeCall(TestReceiver.decrement, (1)))
        );
        PackedUserOperation memory userOp = _userOp(callData);
        bytes32 userOpHash = keccak256("disallowed-selector");
        userOp.signature = abi.encode(sessionKey, _signature(userOpHash, SESSION_KEY));

        vm.expectRevert(
            abi.encodeWithSelector(
                SessionKeyValidator.SessionKeySelectorNotAllowed.selector,
                address(receiver),
                TestReceiver.decrement.selector
            )
        );
        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function test_RevertWhenSessionKeyBatchContainsDisallowedCall() public {
        _configureSession(uint48(block.timestamp + 1 days), 10, 100);
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(receiver), value: 0, data: abi.encodeCall(TestReceiver.increment, (1))
        });
        calls[1] = BaseAccount.Call({
            target: address(receiver), value: 0, data: abi.encodeCall(TestReceiver.decrement, (1))
        });

        PackedUserOperation memory userOp =
            _userOp(abi.encodeCall(AegisAccount.executeBatch, (calls)));
        bytes32 userOpHash = keccak256("disallowed-batch");
        userOp.signature = abi.encode(sessionKey, _signature(userOpHash, SESSION_KEY));

        vm.expectRevert(
            abi.encodeWithSelector(
                SessionKeyValidator.SessionKeySelectorNotAllowed.selector,
                address(receiver),
                TestReceiver.decrement.selector
            )
        );
        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function test_RevertWhenSessionKeyIsRevoked() public {
        _configureSession(uint48(block.timestamp + 1 days), 10, 100);
        _executeAsAccount(abi.encodeWithSignature("revokeSessionKey(address)", sessionKey));

        PackedUserOperation memory userOp = _userOp(
            abi.encodeCall(
                AegisAccount.execute,
                (address(receiver), 0, abi.encodeCall(TestReceiver.increment, (1)))
            )
        );
        bytes32 userOpHash = keccak256("revoked-session");
        userOp.signature = abi.encode(sessionKey, _signature(userOpHash, SESSION_KEY));

        vm.expectRevert(SessionKeyValidator.SessionKeyRevokedError.selector);
        vm.prank(address(entryPoint));
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function test_GuardianRecoveryRequiresThresholdAndDelay() public {
        address guardianOne = address(0x1001);
        address guardianTwo = address(0x1002);
        address recoveredOwner = address(0xCAFE);
        address[] memory guardianList = new address[](2);
        guardianList[0] = guardianOne;
        guardianList[1] = guardianTwo;

        _executeAsAccount(
            abi.encodeWithSignature(
                "configureGuardians(address[],uint16,uint48)", guardianList, 2, uint48(1 days)
            )
        );

        vm.prank(guardianOne);
        bytes32 proposalId = account.proposeRecovery(recoveredOwner);

        vm.expectRevert(RecoveryModule.RecoveryNotReady.selector);
        account.finalizeRecovery(proposalId);

        vm.prank(guardianTwo);
        account.approveRecovery(proposalId);

        vm.expectRevert(RecoveryModule.RecoveryNotReady.selector);
        account.finalizeRecovery(proposalId);

        vm.warp(block.timestamp + 1 days);
        account.finalizeRecovery(proposalId);

        assertEq(account.owner(), recoveredOwner);
    }

    function test_GuardianDuplicateApprovalAndCancellation() public {
        address guardianOne = address(0x2001);
        address guardianTwo = address(0x2002);
        address[] memory guardianList = new address[](2);
        guardianList[0] = guardianOne;
        guardianList[1] = guardianTwo;
        _executeAsAccount(
            abi.encodeWithSignature(
                "configureGuardians(address[],uint16,uint48)", guardianList, 2, uint48(1 days)
            )
        );

        vm.prank(guardianOne);
        bytes32 proposalId = account.proposeRecovery(address(0xBEEF));

        vm.expectRevert(RecoveryModule.RecoveryAlreadyApproved.selector);
        vm.prank(guardianOne);
        account.approveRecovery(proposalId);

        vm.prank(guardianTwo);
        account.cancelRecovery(proposalId);

        vm.expectRevert(RecoveryModule.RecoveryCancelledError.selector);
        account.finalizeRecovery(proposalId);
    }

    function _configureSession(uint48 expiresAt, uint256 maxValue, uint256 limit) internal {
        _executeAsAccount(
            abi.encodeWithSignature(
                "configureSessionKey(address,uint48,uint256,uint256)",
                sessionKey,
                expiresAt,
                maxValue,
                limit
            )
        );
        _executeAsAccount(
            abi.encodeWithSignature(
                "setSessionKeyTarget(address,address,bool)", sessionKey, address(receiver), true
            )
        );
        _executeAsAccount(
            abi.encodeWithSignature(
                "setSessionKeySelector(address,address,bytes4,bool)",
                sessionKey,
                address(receiver),
                TestReceiver.increment.selector,
                true
            )
        );
    }

    function _executeAsAccount(bytes memory data) internal {
        vm.prank(address(entryPoint));
        account.execute(address(account), 0, data);
    }

    function _userOp(bytes memory callData)
        internal
        view
        returns (PackedUserOperation memory userOp)
    {
        userOp.sender = address(account);
        userOp.callData = callData;
    }

    function _signature(bytes32 digest, uint256 privateKey) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}

contract TestReceiver {
    uint256 public total;

    function increment(uint256 amount) external {
        total += amount;
    }

    function decrement(uint256 amount) external {
        total -= amount;
    }
}
