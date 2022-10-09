// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERC721Extended is IERC721 {
    function mintLiquidityLockNFT(address _to, uint256 _tokenId) external;

    function burn(uint256 _tokenId) external;

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        returns (uint256);

    function transferOwnership(address _newOwner) external;
}
