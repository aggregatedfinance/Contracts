// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMerkleDistributor.sol";

/// @custom:security-contact team@aggregated.finance
contract Airdrop is Ownable, IMerkleDistributor {
    /// @notice The address of the Aggregated Finance token
    IERC20 public immutable agfiv1;
    IERC20 public immutable override token;

    bytes32 public immutable override merkleRoot;
    mapping(uint256 => uint256) private claimedBitMap;

    bool public claimsEnabled = true;
    // mapping (address => bool) private hasClaimed;

    constructor(address _v1, address _v2, bytes32 _merkleRoot)
    {
      agfiv1 = IERC20(_v1);
      token = IERC20(_v2);
      merkleRoot = _merkleRoot;
    }

    function enable() external onlyOwner {
      require(!claimsEnabled, "Airdrop::enable: Contract already enabled.");
      claimsEnabled = true;
    }

    function disable() external onlyOwner {
      require(claimsEnabled, "Airdrop::disable: Contract already disabled.");
      claimsEnabled = false;
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override {
      require(claimsEnabled, "Airdrop::claim: Claims not enabled.");
      require(!isClaimed(index), "Airdrop::claim: Drop already claimed.");

      bytes32 node = keccak256(abi.encodePacked(index, account, amount));
      require(MerkleProof.verify(merkleProof, merkleRoot, node), "Airdrop::claim: Invalid proof.");

      uint256 currentBalance = agfiv1.balanceOf(msg.sender);
      require(currentBalance > 0, "Airdrop::claim: Invalid AGFIv1 Balance.");

      _setClaimed(index);
      if (currentBalance > amount) {
        // if they hold more than they're eligible for, then send the eligible amount only
        require(agfiv1.transferFrom(msg.sender, address(this), amount), "Airdrop::claim: Deposit v1 failed.");
        require(token.transfer(msg.sender, amount), "Airdrop::claim: Transfer failed.");
        emit Claimed(index, msg.sender, amount);
      } else {
        // otherwise send what their current balance is, which will either be amount or something smaller
        require(agfiv1.transferFrom(msg.sender, address(this), currentBalance), "Airdrop::claim: Deposit v1 failed.");
        require(token.transfer(msg.sender, currentBalance), "Airdrop::claim: Transfer failed.");
        emit Claimed(index, msg.sender, currentBalance);
      }
    }

    function withdrawv1() external onlyOwner {
      require(agfiv1.transfer(msg.sender, agfiv1.balanceOf(address(this))), "Airdrop::withdrawv1: Withdraw failed.");
    }
}
