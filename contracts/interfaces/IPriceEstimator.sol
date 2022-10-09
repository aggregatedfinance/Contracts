// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceEstimator {
    function getEstimatedETHforERC20(uint256 erc20Amount, address token)
        external
        view
        returns (uint256[] memory);

    function getEstimatedERC20forETH(
        uint256 etherAmountInWei,
        address tokenAddress
    ) external view returns (uint256[] memory);
}
