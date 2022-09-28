// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "../@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LaunchUpgradeProxy is TransparentUpgradeableProxy {
    constructor(
        address admin,
        address logic,
        bytes memory data
    ) TransparentUpgradeableProxy(logic, admin, data) {}
}
