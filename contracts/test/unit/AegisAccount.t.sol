// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { BaseAccount } from "@account-abstraction/core/BaseAccount.sol";
import { EntryPoint } from "@account-abstraction/core/EntryPoint.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { AegisAccount } from "../../src/AegisAccount.sol";

contract AegisAccountTest is Test {
    uint256 internal constant OWNER_KEY = 0xA11CE;

    EntryPoint internal entryPoint;
    AegisAccount internal account;
    address internal owner;

    function setUp() public {
        entryPoint = new EntryPoint();
        owner = vm.addr(OWNER_KEY);
        account = new AegisAccount(entryPoint, owner);
    }

    function test_ConstructorSetsImmutableSecurityBoundary() public view {
        assertEq(address(account.entryPoint()), address(entryPoint));
        assertEq(account.owner(), owner);
    }

    function test_RevertWhenDirectCallerExecutes() public {
        vm.expectRevert(AegisAccount.NotEntryPoint.selector);
        vm.prank(owner);
        account.execute(address(this), 0, "");
    }

    function test_ValidateUserOpAcceptsOwnerSignature() public {
        bytes32 userOpHash = keccak256("aegis-user-op");
        PackedUserOperation memory userOp = _emptyUserOp();
        userOp.signature = _signature(userOpHash, OWNER_KEY);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0);
    }

    function test_ValidateUserOpRejectsInvalidSignatureWithoutReverting() public {
        bytes32 userOpHash = keccak256("aegis-user-op");
        PackedUserOperation memory userOp = _emptyUserOp();
        userOp.signature = _signature(userOpHash, 0xB0B);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1);
    }

    function test_ValidateUserOpRejectsModifiedHash() public {
        bytes32 signedHash = keccak256("aegis-user-op");
        bytes32 modifiedHash = keccak256("modified-user-op");
        PackedUserOperation memory userOp = _emptyUserOp();
        userOp.signature = _signature(signedHash, OWNER_KEY);

        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, modifiedHash, 0);

        assertEq(validationData, 1);
    }

    function test_ValidateUserOpSupportsErc1271Owner() public {
        Mock1271Owner contractOwner = new Mock1271Owner();
        AegisAccount contractOwnedAccount = new AegisAccount(entryPoint, address(contractOwner));
        PackedUserOperation memory userOp = _emptyUserOp();
        userOp.sender = address(contractOwnedAccount);
        userOp.signature = hex"1234";

        vm.prank(address(entryPoint));
        uint256 validationData =
            contractOwnedAccount.validateUserOp(userOp, keccak256("contract-owner-op"), 0);

        assertEq(validationData, 0);
    }

    function test_RevertWhenValidateUserOpCalledByWrongEntryPoint() public {
        PackedUserOperation memory userOp = _emptyUserOp();

        vm.expectRevert(AegisAccount.NotEntryPoint.selector);
        vm.prank(address(0xBEEF));
        account.validateUserOp(userOp, keccak256("hash"), 0);
    }

    function test_SetOwnerRequiresAccountSelfCall() public {
        address newOwner = address(0xCAFE);

        vm.expectRevert(AegisAccount.NotSelf.selector);
        vm.prank(owner);
        account.setOwner(newOwner);

        vm.prank(address(entryPoint));
        account.execute(address(account), 0, abi.encodeCall(AegisAccount.setOwner, (newOwner)));

        assertEq(account.owner(), newOwner);
    }

    function test_AtomicBatchRevertsAndRollsBackState() public {
        TestReceiver receiver = new TestReceiver();
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call({
            target: address(receiver), value: 0, data: abi.encodeCall(TestReceiver.increment, (7))
        });
        calls[1] = BaseAccount.Call({
            target: address(receiver), value: 0, data: abi.encodeCall(TestReceiver.fail, ())
        });

        vm.expectRevert();
        vm.prank(address(entryPoint));
        account.executeBatch(calls);

        assertEq(receiver.total(), 0);
    }

    function test_ExecuteTransfersNativeEth() public {
        vm.deal(address(account), 1 ether);
        uint256 startingBalance = address(this).balance;

        vm.prank(address(entryPoint));
        account.execute(address(this), 0.25 ether, "");

        assertEq(address(this).balance, startingBalance + 0.25 ether);
    }

    function test_ExecuteTransfersErc20() public {
        MockERC20 token = new MockERC20();
        token.mint(address(account), 100 ether);

        vm.prank(address(entryPoint));
        account.execute(
            address(token), 0, abi.encodeCall(MockERC20.transfer, (address(this), 40 ether))
        );

        assertEq(token.balanceOf(address(this)), 40 ether);
        assertEq(token.balanceOf(address(account)), 60 ether);
    }

    function _emptyUserOp() internal view returns (PackedUserOperation memory userOp) {
        userOp.sender = address(account);
    }

    function _signature(bytes32 digest, uint256 privateKey) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    receive() external payable { }
}

contract TestReceiver {
    error FailedCall();

    uint256 internal _total;

    function increment(uint256 amount) external {
        _total += amount;
    }

    function fail() external pure {
        revert FailedCall();
    }

    function total() external view returns (uint256) {
        return _total;
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract Mock1271Owner {
    bytes4 internal constant MAGIC_VALUE = 0x1626ba7e;

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return MAGIC_VALUE;
    }
}
