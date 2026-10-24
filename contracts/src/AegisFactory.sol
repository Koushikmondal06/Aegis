// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AegisAccount } from "./AegisAccount.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/// @title AegisFactory
/// @notice Counterfactual factory for AegisAccount instances.
/// @dev ERC-4337 v0.8 requires sender creation to be performed by EntryPoint's
///      SenderCreator. Restricting this entry point prevents arbitrary callers
///      from deploying an account with unexpected initialization semantics.
contract AegisFactory {
    error OnlySenderCreator();
    error InvalidEntryPoint();

    event AccountCreated(address indexed account, address indexed owner, uint256 indexed salt);

    IEntryPoint public immutable ENTRY_POINT;

    constructor(IEntryPoint _entryPoint) {
        if (address(_entryPoint) == address(0)) revert InvalidEntryPoint();
        ENTRY_POINT = _entryPoint;
    }

    /// @notice Deploy or return the deterministic account for an owner and salt.
    /// @dev The caller must be EntryPoint's SenderCreator contract.
    function createAccount(address owner, uint256 salt) external returns (AegisAccount account) {
        if (msg.sender != address(ENTRY_POINT.senderCreator())) revert OnlySenderCreator();

        address predicted = getAddress(owner, salt);
        if (predicted.code.length != 0) {
            return AegisAccount(payable(predicted));
        }

        account = new AegisAccount{ salt: bytes32(salt) }(ENTRY_POINT, owner);
        emit AccountCreated(address(account), owner, salt);
    }

    /// @notice Predict the account address before deployment.
    function getAddress(address owner, uint256 salt) public view returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(AegisAccount).creationCode, abi.encode(ENTRY_POINT, owner))
        );
        return Create2.computeAddress(bytes32(salt), initCodeHash, address(this));
    }
}
