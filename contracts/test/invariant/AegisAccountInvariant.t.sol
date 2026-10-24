// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";

contract AegisAccountInvariantTest is StdInvariant, Test {
    EntryPoint internal entryPoint;
    AegisAccount internal account;
    address internal immutable initialOwner = address(0xA11CE);

    function setUp() public {
        entryPoint = new EntryPoint();
        account = new AegisAccount(entryPoint, initialOwner);
        targetContract(address(this));
    }

    function attemptDirectOwnerChange(address proposedOwner) external {
        try account.setOwner(proposedOwner) { } catch { }
    }

    function invariant_DirectCallersCannotReplaceOwner() public {
        assertEq(account.owner(), initialOwner);
    }

    function invariant_EntryPointBoundaryIsImmutable() public {
        assertEq(address(account.entryPoint()), address(entryPoint));
    }
}
