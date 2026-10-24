// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { _packValidationData } from "@account-abstraction/core/Helpers.sol";
import { UserOperationLib } from "@account-abstraction/core/UserOperationLib.sol";
import { IEntryPoint } from "@account-abstraction/interfaces/IEntryPoint.sol";
import { IPaymaster } from "@account-abstraction/interfaces/IPaymaster.sol";
import { PackedUserOperation } from "@account-abstraction/interfaces/PackedUserOperation.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title AegisPaymaster
/// @notice An explicitly allowlisted, signer-authorized ERC-4337 v0.8 paymaster.
/// @dev This first implementation sponsors only single-call AegisAccount.execute
///      operations. Reservations are recorded during validation and settled in
///      postOp so a bundle cannot oversubscribe the configured budget.
contract AegisPaymaster is IPaymaster {
    using UserOperationLib for PackedUserOperation;

    bytes4 public constant ACCOUNT_EXECUTE_SELECTOR =
        bytes4(keccak256("execute(address,uint256,bytes)"));
    bytes32 public constant SPONSORSHIP_TYPEHASH = keccak256(
        "AegisSponsorship(address paymaster,uint256 chainId,address sender,uint256 nonce,bytes32 initCodeHash,bytes32 callDataHash,address target,bytes4 selector,uint256 maxCost,uint48 validUntil,uint48 validAfter)"
    );

    IEntryPoint public immutable ENTRY_POINT;
    address public admin;
    address public sponsorSigner;

    uint256 public budget;
    uint256 public spent;
    uint256 public reserved;

    mapping(address => bool) public approvedAccounts;
    mapping(address => bool) public approvedTargets;
    mapping(address => mapping(bytes4 => bool)) public approvedSelectors;

    struct SponsorshipRequest {
        uint48 validUntil;
        uint48 validAfter;
        uint256 maxCost;
        bytes signature;
    }

    error OnlyAdmin();
    error OnlyEntryPoint();
    error InvalidConfiguration();
    error AccountNotApproved();
    error TargetNotApproved(address target);
    error SelectorNotApproved(address target, bytes4 selector);
    error InvalidSponsorshipSignature();
    error SponsorshipExpired();
    error SponsorshipBudgetExceeded();
    error UnsupportedCallData();
    error InvalidPostOpCost();

    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event SponsorSignerChanged(address indexed previousSigner, address indexed newSigner);
    event BudgetChanged(uint256 previousBudget, uint256 newBudget);
    event AccountPolicyChanged(address indexed account, bool approved);
    event TargetPolicyChanged(address indexed target, bool approved);
    event SelectorPolicyChanged(address indexed target, bytes4 indexed selector, bool approved);
    event SponsorshipReserved(bytes32 indexed userOpHash, address indexed account, uint256 maxCost);
    event SponsorshipSettled(
        bytes32 indexed userOpHash, address indexed account, uint256 actualCost
    );

    constructor(IEntryPoint entryPoint_, address admin_, address sponsorSigner_, uint256 budget_) {
        if (
            address(entryPoint_) == address(0) || admin_ == address(0)
                || sponsorSigner_ == address(0)
        ) revert InvalidConfiguration();
        ENTRY_POINT = entryPoint_;
        admin = admin_;
        sponsorSigner = sponsorSigner_;
        budget = budget_;
    }

    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override returns (bytes memory context, uint256 validationData) {
        if (msg.sender != address(ENTRY_POINT)) revert OnlyEntryPoint();
        if (!approvedAccounts[userOp.sender]) revert AccountNotApproved();
        if (userOp.callData.length < 4) revert UnsupportedCallData();

        (address target, bytes4 targetSelector) = _extractTarget(userOp.callData);
        if (!approvedTargets[target]) revert TargetNotApproved(target);
        if (!approvedSelectors[target][targetSelector]) {
            revert SelectorNotApproved(target, targetSelector);
        }

        SponsorshipRequest memory request =
            _decodeSponsorship(userOp.paymasterAndData[UserOperationLib.PAYMASTER_DATA_OFFSET:]);
        if (request.validUntil != 0 && block.timestamp >= request.validUntil) {
            revert SponsorshipExpired();
        }
        if (request.validAfter != 0 && block.timestamp < request.validAfter) {
            revert SponsorshipExpired();
        }
        if (request.maxCost < maxCost || request.maxCost == 0) revert SponsorshipBudgetExceeded();

        bytes32 digest = getSponsorshipDigest(
            userOp, target, targetSelector, request.maxCost, request.validUntil, request.validAfter
        );
        if (!SignatureChecker.isValidSignatureNow(sponsorSigner, digest, request.signature)) {
            revert InvalidSponsorshipSignature();
        }

        if (request.maxCost > budget - spent - reserved) revert SponsorshipBudgetExceeded();
        reserved += request.maxCost;
        emit SponsorshipReserved(userOpHash, userOp.sender, request.maxCost);

        context = abi.encode(userOpHash, userOp.sender, request.maxCost);
        validationData = _packValidationData(false, request.validUntil, request.validAfter);
    }

    function postOp(PostOpMode, bytes calldata context, uint256 actualGasCost, uint256)
        external
        override
    {
        if (msg.sender != address(ENTRY_POINT)) revert OnlyEntryPoint();
        (bytes32 userOpHash, address account, uint256 maxCost) =
            abi.decode(context, (bytes32, address, uint256));
        if (actualGasCost > maxCost || reserved < maxCost) revert InvalidPostOpCost();

        reserved -= maxCost;
        spent += actualGasCost;
        emit SponsorshipSettled(userOpHash, account, actualGasCost);
    }

    function getSponsorshipDigest(
        PackedUserOperation calldata userOp,
        address target,
        bytes4 selector,
        uint256 signedMaxCost,
        uint48 validUntil,
        uint48 validAfter
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SPONSORSHIP_TYPEHASH,
                address(this),
                block.chainid,
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                target,
                selector,
                signedMaxCost,
                validUntil,
                validAfter
            )
        );
        return MessageHashUtils.toEthSignedMessageHash(structHash);
    }

    function setAdmin(address newAdmin) external {
        _onlyAdmin();
        if (newAdmin == address(0)) revert InvalidConfiguration();
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }

    function setSponsorSigner(address newSigner) external {
        _onlyAdmin();
        if (newSigner == address(0)) revert InvalidConfiguration();
        emit SponsorSignerChanged(sponsorSigner, newSigner);
        sponsorSigner = newSigner;
    }

    function setBudget(uint256 newBudget) external {
        _onlyAdmin();
        if (newBudget < spent + reserved) revert InvalidConfiguration();
        emit BudgetChanged(budget, newBudget);
        budget = newBudget;
    }

    function setApprovedAccount(address account, bool approved) external {
        _onlyAdmin();
        approvedAccounts[account] = approved;
        emit AccountPolicyChanged(account, approved);
    }

    function setApprovedTarget(address target, bool approved) external {
        _onlyAdmin();
        approvedTargets[target] = approved;
        emit TargetPolicyChanged(target, approved);
    }

    function setApprovedSelector(address target, bytes4 selector, bool approved) external {
        _onlyAdmin();
        approvedSelectors[target][selector] = approved;
        emit SelectorPolicyChanged(target, selector, approved);
    }

    function deposit() external payable {
        ENTRY_POINT.depositTo{ value: msg.value }(address(this));
    }

    function addStake(uint32 unstakeDelaySec) external payable {
        _onlyAdmin();
        ENTRY_POINT.addStake{ value: msg.value }(unstakeDelaySec);
    }

    function unlockStake() external {
        _onlyAdmin();
        ENTRY_POINT.unlockStake();
    }

    function withdrawStake(address payable withdrawAddress) external {
        _onlyAdmin();
        ENTRY_POINT.withdrawStake(withdrawAddress);
    }

    function withdrawTo(address payable withdrawAddress, uint256 amount) external {
        _onlyAdmin();
        ENTRY_POINT.withdrawTo(withdrawAddress, amount);
    }

    function _extractTarget(bytes calldata callData)
        internal
        pure
        returns (address target, bytes4 targetSelector)
    {
        bytes4 accountSelector;
        assembly ("memory-safe") {
            accountSelector := calldataload(callData.offset)
        }
        if (accountSelector != ACCOUNT_EXECUTE_SELECTOR) revert UnsupportedCallData();

        (address decodedTarget,, bytes memory targetData) =
            abi.decode(callData[4:], (address, uint256, bytes));
        target = decodedTarget;
        if (targetData.length >= 4) {
            assembly ("memory-safe") {
                targetSelector := mload(add(targetData, 32))
            }
        }
    }

    function _decodeSponsorship(bytes calldata data)
        internal
        pure
        returns (SponsorshipRequest memory request)
    {
        (request.validUntil, request.validAfter, request.maxCost, request.signature) =
            abi.decode(data, (uint48, uint48, uint256, bytes));
    }

    function _onlyAdmin() internal view {
        if (msg.sender != admin) revert OnlyAdmin();
    }
}
