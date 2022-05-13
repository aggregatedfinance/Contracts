// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./@openzeppelin/governance/Governor.sol";
import "./@openzeppelin/governance/IGovernor.sol";
import "./@openzeppelin/governance/extensions/GovernorSettings.sol";
import "./@openzeppelin/governance/compatibility/GovernorCompatibilityBravo.sol";
import "./@openzeppelin/governance/extensions/GovernorVotes.sol";
import "./@openzeppelin/governance/extensions/GovernorVotesQuorumFraction.sol";
import "./@openzeppelin/governance/extensions/GovernorTimelockControl.sol";
import "./@openzeppelin/access/Ownable.sol";

contract AggregatedFinanceGovernor is Governor, GovernorSettings, GovernorCompatibilityBravo, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl, Ownable {
    mapping (address => bool) private _proposalManagers;

    event ProposalManagerModified(address proposalManager, bool enabled);
    
    constructor(IVotes _token, TimelockController _timelock)
        Governor("Aggregated Finance Governor")
        GovernorSettings(1 /* 1 block */, 19636 /* 3 days */, 0)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4)
        GovernorTimelockControl(_timelock)
    {
        _proposalManagers[msg.sender] = true;
    }

    // The following functions are overrides required by Solidity.

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function getVotes(address account, uint256 blockNumber)
        public
        view
        override(Governor, IGovernor)
        returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, IGovernor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
        public
        override(Governor, GovernorCompatibilityBravo, IGovernor)
        returns (uint256)
    {
        require(isProposalManager(msg.sender), "Proposals must be opened by ProposalManagers.");
        return super.propose(targets, values, calldatas, description);
    }

    function isProposalManager(address member) public view returns (bool) {
        return _proposalManagers[member];
    }

    function addProposalManager(address proposalManager) external onlyOwner {
        require(proposalManager != address(0), "New ProposalManager cannot be zero address.");
        require(_proposalManagers[proposalManager] == false, "Address already ProposalManager.");
        _proposalManagers[proposalManager] = true;

        emit ProposalManagerModified(proposalManager, true);
    }

    function removeProposalManager(address proposalManager) external onlyOwner {
        require(_proposalManagers[proposalManager] == true, "Address not a ProposalManager.");
        _proposalManagers[proposalManager] = false;

        emit ProposalManagerModified(proposalManager, false);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        internal
        override(Governor, GovernorTimelockControl)
    {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, IERC165, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
