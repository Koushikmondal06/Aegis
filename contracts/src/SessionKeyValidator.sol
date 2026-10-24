// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SIG_VALIDATION_FAILED, _packValidationData } from "@account-abstraction/core/Helpers.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title SessionKeyValidator
/// @notice Conservative, calldata-aware temporary authorization for Aegis accounts.
/// @dev Spending is reserved during validation. This is intentionally conservative:
///      a session-key operation that later reverts still consumes its reserved value.
///      That prevents failed execution paths from becoming a spending-limit bypass.
abstract contract SessionKeyValidator {
    bytes4 internal constant EXECUTE_SELECTOR = bytes4(keccak256("execute(address,uint256,bytes)"));
    bytes4 internal constant EXECUTE_BATCH_SELECTOR =
        bytes4(keccak256("executeBatch((address,uint256,bytes)[])"));

    struct SessionKey {
        uint48 expiresAt;
        uint256 maxValuePerTransaction;
        uint256 spendingLimit;
        uint256 spent;
        bool revoked;
    }

    struct SessionCall {
        address target;
        uint256 value;
        bytes data;
    }

    mapping(address => SessionKey) public sessionKeys;
    mapping(address => mapping(address => bool)) public sessionKeyTargets;
    mapping(address => mapping(address => mapping(bytes4 => bool))) public sessionKeySelectors;

    error SessionKeyInvalid();
    error SessionKeyExpired();
    error SessionKeyRevokedError();
    error SessionKeyTargetNotAllowed(address target);
    error SessionKeySelectorNotAllowed(address target, bytes4 selector);
    error SessionKeyValueLimitExceeded();
    error SessionKeySpendingLimitExceeded();
    error InvalidSessionConfiguration();

    event SessionKeyConfigured(
        address indexed sessionKey,
        uint48 expiresAt,
        uint256 maxValuePerTransaction,
        uint256 spendingLimit
    );
    event SessionKeyTargetConfigured(
        address indexed sessionKey, address indexed target, bool allowed
    );
    event SessionKeySelectorConfigured(
        address indexed sessionKey, address indexed target, bytes4 indexed selector, bool allowed
    );
    event SessionKeyRevoked(address indexed sessionKey);

    function configureSessionKey(
        address sessionKey,
        uint48 expiresAt,
        uint256 maxValuePerTransaction,
        uint256 spendingLimit
    ) external {
        _requireSessionAdmin();
        if (
            sessionKey == address(0) || expiresAt <= block.timestamp
                || maxValuePerTransaction > spendingLimit
        ) revert InvalidSessionConfiguration();

        sessionKeys[sessionKey] = SessionKey({
            expiresAt: expiresAt,
            maxValuePerTransaction: maxValuePerTransaction,
            spendingLimit: spendingLimit,
            spent: 0,
            revoked: false
        });
        emit SessionKeyConfigured(sessionKey, expiresAt, maxValuePerTransaction, spendingLimit);
    }

    function setSessionKeyTarget(address sessionKey, address target, bool allowed) external {
        _requireSessionAdmin();
        if (sessionKeys[sessionKey].expiresAt == 0) revert SessionKeyInvalid();
        sessionKeyTargets[sessionKey][target] = allowed;
        emit SessionKeyTargetConfigured(sessionKey, target, allowed);
    }

    function setSessionKeySelector(
        address sessionKey,
        address target,
        bytes4 selector,
        bool allowed
    ) external {
        _requireSessionAdmin();
        if (sessionKeys[sessionKey].expiresAt == 0) revert SessionKeyInvalid();
        sessionKeySelectors[sessionKey][target][selector] = allowed;
        emit SessionKeySelectorConfigured(sessionKey, target, selector, allowed);
    }

    function revokeSessionKey(address sessionKey) external {
        _requireSessionAdmin();
        if (sessionKeys[sessionKey].expiresAt == 0) revert SessionKeyInvalid();
        sessionKeys[sessionKey].revoked = true;
        emit SessionKeyRevoked(sessionKey);
    }

    function _validateSessionKey(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        returns (uint256 validationData)
    {
        (address sessionKey, bytes memory signature) =
            abi.decode(userOp.signature, (address, bytes));
        SessionKey storage policy = sessionKeys[sessionKey];
        if (sessionKey == address(0) || policy.expiresAt == 0) revert SessionKeyInvalid();
        if (policy.revoked) revert SessionKeyRevokedError();
        if (block.timestamp >= policy.expiresAt) revert SessionKeyExpired();
        if (!SignatureChecker.isValidSignatureNow(sessionKey, userOpHash, signature)) {
            return SIG_VALIDATION_FAILED;
        }

        uint256 totalValue =
            _validateCallPermissions(sessionKey, userOp.callData, policy.maxValuePerTransaction);
        if (totalValue > policy.spendingLimit - policy.spent) {
            revert SessionKeySpendingLimitExceeded();
        }
        policy.spent += totalValue;

        return _packValidationData(false, policy.expiresAt, 0);
    }

    function _validateCallPermissions(
        address sessionKey,
        bytes calldata callData,
        uint256 maxValuePerTransaction
    ) internal view returns (uint256 totalValue) {
        if (callData.length < 4) revert SessionKeyInvalid();
        bytes4 outerSelector;
        assembly ("memory-safe") {
            outerSelector := calldataload(callData.offset)
        }

        if (outerSelector == EXECUTE_SELECTOR) {
            (address target, uint256 value, bytes memory data) =
                abi.decode(callData[4:], (address, uint256, bytes));
            _validateSingleCall(sessionKey, target, value, data, maxValuePerTransaction);
            return value;
        }

        if (outerSelector == EXECUTE_BATCH_SELECTOR) {
            SessionCall[] memory calls = abi.decode(callData[4:], (SessionCall[]));
            if (calls.length == 0) revert SessionKeyInvalid();
            for (uint256 i = 0; i < calls.length; i++) {
                SessionCall memory call = calls[i];
                _validateSingleCall(
                    sessionKey, call.target, call.value, call.data, maxValuePerTransaction
                );
                totalValue += call.value;
            }
            return totalValue;
        }

        revert SessionKeyInvalid();
    }

    function _validateSingleCall(
        address sessionKey,
        address target,
        uint256 value,
        bytes memory data,
        uint256 maxValuePerTransaction
    ) internal view {
        if (!sessionKeyTargets[sessionKey][target]) {
            revert SessionKeyTargetNotAllowed(target);
        }
        if (value > maxValuePerTransaction) revert SessionKeyValueLimitExceeded();

        bytes4 selector;
        if (data.length >= 4) {
            assembly ("memory-safe") {
                selector := mload(add(data, 32))
            }
        }
        if (!sessionKeySelectors[sessionKey][target][selector]) {
            revert SessionKeySelectorNotAllowed(target, selector);
        }
    }

    function _requireSessionAdmin() internal view virtual;
}
