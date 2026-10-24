// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";
import { AegisFactory } from "../../src/AegisFactory.sol";

contract AegisFactoryTest is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;

    EntryPoint internal entryPoint;
    AegisFactory internal factory;
    address internal owner;

    function setUp() public {
        entryPoint = new EntryPoint();
        factory = new AegisFactory(entryPoint);
        owner = vm.addr(OWNER_KEY);
    }

    function test_GetAddressMatchesDeployment() public {
        uint256 salt = 42;
        address predicted = factory.getAddress(owner, salt);

        vm.prank(address(entryPoint.senderCreator()));
        AegisAccount account = factory.createAccount(owner, salt);

        assertEq(address(account), predicted);
        assertEq(account.owner(), owner);
        assertEq(address(account.entryPoint()), address(entryPoint));
        assertGt(address(account).code.length, 0);
    }

    function test_DuplicateDeploymentReturnsExistingAccount() public {
        uint256 salt = 7;

        vm.prank(address(entryPoint.senderCreator()));
        AegisAccount first = factory.createAccount(owner, salt);

        vm.prank(address(entryPoint.senderCreator()));
        AegisAccount second = factory.createAccount(owner, salt);

        assertEq(address(first), address(second));
        assertEq(first.owner(), owner);
    }

    function test_RevertWhenCallerIsNotSenderCreator() public {
        vm.expectRevert(AegisFactory.OnlySenderCreator.selector);
        factory.createAccount(owner, 1);
    }

    function test_DifferentOwnersOrSaltsProduceDifferentAddresses() public view {
        address otherOwner = vm.addr(0xB0B);

        assertTrue(factory.getAddress(owner, 1) != factory.getAddress(otherOwner, 1));
        assertTrue(factory.getAddress(owner, 1) != factory.getAddress(owner, 2));
    }
}
