// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISignataRight {
    function holdsTokenOfSchema(address holder, uint256 schemaId) external view returns (bool);
}