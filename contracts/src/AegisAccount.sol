// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import {
    SIG_VALIDATION_FAILED,
    SIG_VALIDATION_SUCCESS
} from "@account-abstraction/core/Helpers.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { Exec } from "@account-abstraction/utils/Exec.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { RecoveryModule } from "./RecoveryModule.sol";
import { SessionKeyValidator } from "./SessionKeyValidator.sol";

/// @title AegisAccount
/// @notice A minimal, owner-controlled ERC-4337 account for the Aegis platform.
/// @dev All account execution is routed through the configured EntryPoint. The
///      constructor is intentionally the only initialization path, so an account
///      deployed by the factory cannot be initialized a second time.
contract AegisAccount is BaseAccount, SessionKeyValidator, RecoveryModule {
    error InvalidEntryPoint();
    error InvalidOwner();
    error NotEntryPoint();
    error NotSelf();

    event AccountInitialized(address indexed entryPoint, address indexed owner);
    event Executed(address indexed target, uint256 value, bytes4 indexed selector);
    event BatchExecuted(uint256 indexed callCount);
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);

    IEntryPoint private immutable _ENTRY_POINT;
    address public owner;

    constructor(IEntryPoint entryPoint_, address owner_) {
        if (address(entryPoint_) == address(0)) revert InvalidEntryPoint();
        if (owner_ == address(0)) revert InvalidOwner();

        _ENTRY_POINT = entryPoint_;
        owner = owner_;

        emit AccountInitialized(address(entryPoint_), owner_);
    }

    function entryPoint() public view override returns (IEntryPoint) {
        return _ENTRY_POINT;
    }

    /// @inheritdoc BaseAccount
    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        override
        returns (uint256 validationData)
    {
        bool valid = SignatureChecker.isValidSignatureNow(owner, userOpHash, userOp.signature);
        if (valid || userOp.signature.length == 65) {
            return valid ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
        }

        return _validateSessionKey(userOp, userOpHash);
    }

    function _requireFromEntryPoint() internal view override {
        if (msg.sender != address(_ENTRY_POINT)) revert NotEntryPoint();
    }

    /// @notice Execute one call after EntryPoint validation.
    function execute(address target, uint256 value, bytes calldata data) external override {
        _requireForExecute();

        bool success = Exec.call(target, value, data, gasleft());
        if (!success) Exec.revertWithReturnData();

        bytes4 selector;
        if (data.length >= 4) {
            assembly ("memory-safe") {
                selector := calldataload(data.offset)
            }
        }
        emit Executed(target, value, selector);
    }

    /// @notice Execute calls in order and revert the entire batch if any call fails.
    function executeBatch(BaseAccount.Call[] calldata calls) external override {
        _requireForExecute();

        uint256 callsLength = calls.length;
        for (uint256 i = 0; i < callsLength; i++) {
            BaseAccount.Call calldata call = calls[i];
            bool success = Exec.call(call.target, call.value, call.data, gasleft());
            if (!success) {
                if (callsLength == 1) {
                    Exec.revertWithReturnData();
                }
                revert ExecuteError(i, Exec.getReturnData(0));
            }
        }

        emit BatchExecuted(calls.length);
    }

    /// @notice Change ownership through an account self-call made by a validated UserOperation.
    /// @dev Direct calls by the current EOA owner are intentionally rejected.
    function setOwner(address newOwner) external {
        _setOwnerFromAuthorizedPath(newOwner);
    }

    function _setOwnerFromAuthorizedPath(address newOwner) internal {
        if (msg.sender != address(this)) revert NotSelf();
        if (newOwner == address(0)) revert InvalidOwner();

        address previousOwner = owner;
        owner = newOwner;
        emit OwnerChanged(previousOwner, newOwner);
    }

    function _requireSessionAdmin() internal view override {
        if (msg.sender != address(this)) revert NotSelf();
    }

    function _recoveryOwner() internal view override returns (address) {
        return owner;
    }

    function _setRecoveryOwner(address newOwner) internal override {
        if (newOwner == address(0)) revert InvalidOwner();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnerChanged(previousOwner, newOwner);
    }

    function _requireRecoveryAdmin() internal view override {
        if (msg.sender != address(this)) revert NotSelf();
    }

    receive() external payable { }
}
