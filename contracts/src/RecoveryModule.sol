// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title RecoveryModule
/// @notice Delayed guardian-based owner recovery with explicit proposal identities.
/// @dev Guardian and recovery configuration is only reachable through the account's
///      self-call authorization path. Guardians can propose, approve, or cancel;
///      finalization is permissionless after threshold and delay requirements pass.
abstract contract RecoveryModule {
    struct RecoveryProposal {
        address newOwner;
        uint48 executeAfter;
        uint16 approvals;
        bool cancelled;
    }

    mapping(address => bool) public guardians;
    address[] private _guardianList;
    mapping(bytes32 => RecoveryProposal) public recoveryProposals;
    mapping(bytes32 => mapping(address => bool)) public recoveryApprovals;

    uint16 public recoveryThreshold;
    uint48 public recoveryDelay;
    uint256 public recoveryNonce;

    error RecoveryNotAuthorized();
    error InvalidGuardianConfiguration();
    error InvalidRecoveryProposal();
    error RecoveryAlreadyApproved();
    error RecoveryNotReady();
    error RecoveryCancelledError();

    event GuardiansConfigured(address[] guardians, uint16 threshold, uint48 delay);
    event RecoveryProposed(
        bytes32 indexed proposalId, address indexed proposer, address indexed newOwner
    );
    event RecoveryApproved(bytes32 indexed proposalId, address indexed guardian, uint16 approvals);
    event RecoveryCancelled(bytes32 indexed proposalId, address indexed canceller);
    event RecoveryFinalized(
        bytes32 indexed proposalId, address indexed previousOwner, address indexed newOwner
    );

    function configureGuardians(address[] calldata newGuardians, uint16 threshold, uint48 delay)
        external
    {
        _requireRecoveryAdmin();
        if (newGuardians.length == 0 || threshold == 0 || threshold > newGuardians.length) {
            revert InvalidGuardianConfiguration();
        }
        if (delay < 1 hours) revert InvalidGuardianConfiguration();

        for (uint256 i = 0; i < _guardianList.length; i++) {
            guardians[_guardianList[i]] = false;
        }
        delete _guardianList;

        for (uint256 i = 0; i < newGuardians.length; i++) {
            address guardian = newGuardians[i];
            if (guardian == address(0) || guardians[guardian]) {
                revert InvalidGuardianConfiguration();
            }
            guardians[guardian] = true;
            _guardianList.push(guardian);
        }

        recoveryThreshold = threshold;
        recoveryDelay = delay;
        emit GuardiansConfigured(newGuardians, threshold, delay);
    }

    function getGuardians() external view returns (address[] memory) {
        return _guardianList;
    }

    function proposeRecovery(address newOwner) external returns (bytes32 proposalId) {
        if (!guardians[msg.sender] || newOwner == address(0)) revert RecoveryNotAuthorized();
        if (recoveryThreshold == 0) revert InvalidGuardianConfiguration();

        proposalId = keccak256(abi.encode(address(this), block.chainid, recoveryNonce++, newOwner));
        recoveryProposals[proposalId] = RecoveryProposal({
            newOwner: newOwner,
            executeAfter: uint48(block.timestamp) + recoveryDelay,
            approvals: 1,
            cancelled: false
        });
        recoveryApprovals[proposalId][msg.sender] = true;
        emit RecoveryProposed(proposalId, msg.sender, newOwner);
        emit RecoveryApproved(proposalId, msg.sender, 1);
    }

    function approveRecovery(bytes32 proposalId) external {
        if (!guardians[msg.sender]) revert RecoveryNotAuthorized();
        RecoveryProposal storage proposal = recoveryProposals[proposalId];
        if (proposal.newOwner == address(0)) revert InvalidRecoveryProposal();
        if (proposal.cancelled) revert RecoveryCancelledError();
        if (recoveryApprovals[proposalId][msg.sender]) revert RecoveryAlreadyApproved();

        recoveryApprovals[proposalId][msg.sender] = true;
        proposal.approvals += 1;
        emit RecoveryApproved(proposalId, msg.sender, proposal.approvals);
    }

    function cancelRecovery(bytes32 proposalId) external {
        if (msg.sender != _recoveryOwner() && !guardians[msg.sender]) {
            revert RecoveryNotAuthorized();
        }
        RecoveryProposal storage proposal = recoveryProposals[proposalId];
        if (proposal.newOwner == address(0)) revert InvalidRecoveryProposal();
        if (proposal.cancelled) revert RecoveryCancelledError();

        proposal.cancelled = true;
        emit RecoveryCancelled(proposalId, msg.sender);
    }

    function finalizeRecovery(bytes32 proposalId) external {
        RecoveryProposal storage proposal = recoveryProposals[proposalId];
        if (proposal.newOwner == address(0)) revert InvalidRecoveryProposal();
        if (proposal.cancelled) revert RecoveryCancelledError();
        if (proposal.approvals < recoveryThreshold || block.timestamp < proposal.executeAfter) {
            revert RecoveryNotReady();
        }

        address previousOwner = _recoveryOwner();
        _setRecoveryOwner(proposal.newOwner);
        delete recoveryProposals[proposalId];
        emit RecoveryFinalized(proposalId, previousOwner, proposal.newOwner);
    }

    function _recoveryOwner() internal view virtual returns (address);
    function _setRecoveryOwner(address newOwner) internal virtual;
    function _requireRecoveryAdmin() internal view virtual;
}
