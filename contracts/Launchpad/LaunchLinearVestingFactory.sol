// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./LaunchUpgradeProxy.sol";
import "../@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ILaunchLinearVesting.sol";
import "./ISignataRight.sol";

/// @title LaunchFactory
/// @notice Use to deploy Launch contracts on chain
contract LaunchLinearVestingFactory is AccessControlEnumerable, Initializable {
    ILaunchLinearVesting[] public LaunchLinearVestingImplementations;
    uint256 public LaunchLinearVestingVersion;

    ILaunchLinearVesting[] public deployedLaunchContracts;
    address public launchProxyAdmin;
    address public launchAdmin;
    address public paymentAddress;
    uint256 public listFee;
    ISignataRight signataRight;
    uint256 schemaId;

    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER");

    event LaunchLinearVestingCreated(ILaunchLinearVesting indexed newLaunch);
    event PushLaunchLinearVestingVersion(
        ILaunchLinearVesting indexed newLaunch,
        uint256 newVersionId
    );
    event SetLaunchLinearVestingVersion(
        uint256 previousVersionId,
        uint256 newVersionId
    );
    event UpdateLaunchAdmins(
        address previousLaunchProxyAdmin,
        address indexed newLaunchProxyAdmin,
        address indexed previousLaunchAdmin,
        address indexed newLaunchAdmin
    );
    event SweepWithdraw(
        address indexed receiver,
        IERC20 indexed token,
        uint256 balance
    );
    event UpdateListFee(uint256 previousListFee, uint256 newListFee);

    /// @notice Constructor
    /// @param _factoryAdmin: Admin to set creation roles.
    /// @param _launchProxyAdmin: Admin of the proxy deployed for Launchs. This address has the power to upgrade the LaunchLinearVesting Contract
    /// @param _launchAdmin: Admin of the Launchs. This address has the power to change Launch settings
    /// @param _implementation: Address of the implementation contract to use.
    function initialize(
        address _factoryAdmin,
        address _launchProxyAdmin,
        address _launchAdmin,
        ILaunchLinearVesting _implementation,
        address _paymentAddress,
        uint256 _listFee
    ) external initializer {
        require(
            _launchProxyAdmin != _launchAdmin,
            "launchProxyAdmin and launchAdmin cannot be the same"
        );
        // Setup access control
        _setupRole(DEFAULT_ADMIN_ROLE, _factoryAdmin);
        _setupRole(DEPLOYER_ROLE, _factoryAdmin);
        // Admin role can add new users to deployer role
        _setRoleAdmin(DEPLOYER_ROLE, DEFAULT_ADMIN_ROLE);
        _pushImplementationContract(_implementation);

        launchProxyAdmin = _launchProxyAdmin;
        launchAdmin = _launchAdmin;
        paymentAddress = _paymentAddress;
        listFee = _listFee;
    }

    /// @notice Deploy a new LaunchLinearVesting contract based on the current implementation version
    function deployNewLaunchLinearVesting(
        IERC20 _stakeToken,
        IERC20 _offeringToken,
        uint256 _startBlock,
        uint256 _endBlockOffset,
        uint256 _vestingBlockOffset, // Block offset between vesting distributions
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        bool _onlyAgfiHolders
    ) public onlyRole(DEPLOYER_ROLE) returns (ILaunchLinearVesting newLaunch) {
        LaunchUpgradeProxy newProxy = new LaunchUpgradeProxy(
            launchProxyAdmin,
            address(activeImplementationContract()),
            ""
        );
        newLaunch = ILaunchLinearVesting(address(newProxy));

        newLaunch.initialize(
            _stakeToken,
            _offeringToken,
            _startBlock,
            _endBlockOffset,
            _vestingBlockOffset,
            _offeringAmount,
            _raisingAmount,
            launchAdmin
        );

        if (!_onlyAgfiHolders) {
            (bool success, ) = paymentAddress.call{value: listFee}("");
            require(success, "charge fee failed");
        }

        deployedLaunchContracts.push(newLaunch);
        emit LaunchLinearVestingCreated(newLaunch);
    }

    function configureSignataIntegration(
        ILaunchLinearVesting _launch,
        bool _requireSchemaForLaunch,
        bool _requireSchemaForDeposits,
        bool _onlyAgfiHolders
    ) public onlyRole(DEPLOYER_ROLE) {
        _launch.configureSignataIntegration(
            signataRight,
            schemaId,
            _requireSchemaForLaunch,
            _requireSchemaForDeposits
        );
    }

    /// @notice Get total number of LaunchLinearVesting contracts deployed through this factory
    function getNumberOfDeployedContracts() external view returns (uint256) {
        return deployedLaunchContracts.length;
    }

    /// @notice Returns current active implementation address
    function activeImplementationContract()
        public
        view
        returns (ILaunchLinearVesting)
    {
        return LaunchLinearVestingImplementations[LaunchLinearVestingVersion];
    }

    /// @notice Add and use new implementation
    /// @dev EXTCODESIZE returns 0 if it is called from the constructor of a contract
    function pushImplementationContract(ILaunchLinearVesting _newImplementation)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint32 size;
        assembly {
            size := extcodesize(_newImplementation)
        }
        require(size > 0, "Not a contract");
        _pushImplementationContract(_newImplementation);
    }

    /// @notice Add and use new implementation
    function _pushImplementationContract(
        ILaunchLinearVesting _newImplementation
    ) internal {
        LaunchLinearVestingImplementations.push(_newImplementation);
        LaunchLinearVestingVersion =
            LaunchLinearVestingImplementations.length -
            1;
        emit PushLaunchLinearVestingVersion(
            _newImplementation,
            LaunchLinearVestingVersion
        );
    }

    /// @notice Change active implementation
    function setImplementationContract(uint256 _index)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            _index < LaunchLinearVestingImplementations.length,
            "version out of bounds"
        );
        emit SetLaunchLinearVestingVersion(LaunchLinearVestingVersion, _index);
        LaunchLinearVestingVersion = _index;
    }

    /// @notice change the address of the proxy admin used when deploying new Launch contracts
    /// @dev The proxy admin must be different than the admin of the implementation as calls from proxyAdmin stop at the proxy contract
    function setLaunchAdmins(
        address _newLaunchProxyAdmin,
        address _newLaunchAdmin
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _newLaunchProxyAdmin != _newLaunchAdmin,
            "launchProxyAdmin and launchAdmin cannot be the same"
        );
        emit UpdateLaunchAdmins(
            launchProxyAdmin,
            _newLaunchProxyAdmin,
            launchAdmin,
            _newLaunchAdmin
        );
        launchProxyAdmin = _newLaunchProxyAdmin;
        launchAdmin = _newLaunchAdmin;
    }

    /// @notice A public function to sweep accidental ERC20 transfers to this contract.
    /// @param _tokens Array of ERC20 addresses to sweep
    /// @param _to Address to send tokens to
    function sweepTokens(IERC20[] memory _tokens, address _to)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        for (uint256 index = 0; index < _tokens.length; index++) {
            IERC20 token = _tokens[index];
            uint256 balance = token.balanceOf(address(this));
            token.transfer(_to, balance);
            emit SweepWithdraw(_to, token, balance);
        }
    }

    function updateListFee(uint256 _newListFee)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        listFee = _newListFee;
        emit UpdateListFee(listFee, _newListFee);
    }
}
