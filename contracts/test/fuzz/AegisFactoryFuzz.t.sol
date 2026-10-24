// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";
import { AegisFactory } from "../../src/AegisFactory.sol";

contract AegisFactoryFuzzTest is Test {
    EntryPoint internal entryPoint;
    AegisFactory internal factory;

    function setUp() public {
        entryPoint = new EntryPoint();
        factory = new AegisFactory(entryPoint);
    }

    function testFuzz_PredictedAddressMatchesDeployment(address owner, uint256 salt) public {
        vm.assume(owner != address(0));
        address predicted = factory.getAddress(owner, salt);

        vm.prank(address(entryPoint.senderCreator()));
        AegisAccount account = factory.createAccount(owner, salt);

        assertEq(address(account), predicted);
        assertEq(account.owner(), owner);
    }
}
