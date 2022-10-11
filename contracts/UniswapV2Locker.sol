// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./@openzeppelin/contracts/access/Ownable.sol";
import "./@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ISignataRight.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";

contract UniswapV2Locker is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    IUniswapV2Factory public uniswapFactory;

    struct UserInfo {
        EnumerableSet.AddressSet lockedTokens; // records all tokens the user has locked
        mapping(address => uint256[]) locksForToken; // map erc20 address to lock id for that token
    }

    struct Lock {
        uint256 lockDate; // the date the token was locked
        uint256 amount; // the amount of tokens still locked (initialAmount minus withdrawls)
        uint256 initialAmount; // the initial lock amount
        uint256 unlockDate; // the date the token can be withdrawn
        uint256 lockID; // lockID nonce per uni pair
        address owner;
        uint256 schemaId;
    }

    mapping(address => UserInfo) private users;

    EnumerableSet.AddressSet private lockedTokens;
    mapping(address => Lock[]) public locks; // map univ2 pair to all its locks

    uint256 public nativeFee; // eth fee for creating a lock

    address payable feeAddress;

    // Signata Integration
    ISignataRight public signataRight;

    event Deposited(
        address lpToken,
        address user,
        uint256 amount,
        uint256 lockDate,
        uint256 unlockDate,
        uint256 schemaId
    );
    event Withdrawn(address lpToken, uint256 amount);
    event SignataRightUpdated(address newSignataRight);
    event LockTransferred(address previousOwner, address newOwner);
    event Relocked(uint256 lockId, uint256 unlockDate);
    event LockSplit(uint256 lockId, uint256 amount);

    constructor(IUniswapV2Factory _uniswapFactory, ISignataRight _signataRight) {
        feeAddress = payable(msg.sender);
        nativeFee = 1e18;
        uniswapFactory = _uniswapFactory;
        signataRight = _signataRight;
    }

    function setFeeAddress(address payable _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
    }

    function setFee(uint256 _nativeFee) public onlyOwner {
        nativeFee = _nativeFee;
    }

    /**
     * @notice Creates a new lock
     * @param _lpToken the univ2 token address
     * @param _amount amount of LP tokens to lock
     * @param _unlock_date the unix timestamp (in seconds) until unlock
     * @param _withdrawer the user who can withdraw liquidity once the lock expires.
     */
    function lockTokens(
        address _lpToken,
        uint256 _amount,
        uint256 _unlock_date,
        address payable _withdrawer,
        uint256 _schemaId
    ) external payable nonReentrant {
        require(_unlock_date < 10000000000, "lockTokens::Invalid timestamp"); // prevents errors when timestamp entered in milliseconds
        require(_amount > 0, "lockTokens::Amount needs to be greater than 0");

        // ensure this pair is a univ2 pair by querying the factory
        IUniswapV2Pair lpair = IUniswapV2Pair(address(_lpToken));
        address factoryPairAddress = uniswapFactory.getPair(
            lpair.token0(),
            lpair.token1()
        );
        require(factoryPairAddress == address(_lpToken), "lockTokens::Invalid LP pair");

        // check holding NFT of schema
        if (_schemaId > 0) {
            require(
                signataRight.holdsTokenOfSchema(msg.sender, _schemaId),
                "lockTokens::Sender does not hold NFT of schema"
            );
        }

        SafeERC20.safeTransferFrom(
            IERC20(_lpToken),
            address(msg.sender),
            address(this),
            _amount
        );

        require(msg.value == nativeFee, "lockTokens::Fee not paid");
        feeAddress.transfer(nativeFee);

        Lock memory lock;
        lock.lockDate = block.timestamp;
        lock.amount = _amount;
        lock.initialAmount = _amount;
        lock.unlockDate = _unlock_date;
        lock.lockID = locks[_lpToken].length;
        lock.owner = _withdrawer;
        lock.schemaId = _schemaId;

        // record the lock for the univ2pair
        locks[_lpToken].push(lock);
        lockedTokens.add(_lpToken);

        // record the lock for the user
        UserInfo storage user = users[_withdrawer];
        user.lockedTokens.add(_lpToken);
        uint256[] storage user_locks = user.locksForToken[_lpToken];
        user_locks.push(lock.lockID);

        emit Deposited(
            _lpToken,
            msg.sender,
            lock.amount,
            lock.lockDate,
            lock.unlockDate,
            lock.schemaId
        );
    }

    /**
     * @notice extend a lock with a new unlock date, _index and _lockID ensure the correct lock is changed
     * this prevents errors when a user performs multiple tx per block possibly with varying gas prices
     */
    function relock(
        address _lpToken,
        uint256 _index,
        uint256 _lockID,
        uint256 _unlock_date
    ) external nonReentrant {
        require(_unlock_date < 10000000000, "relock::Invalid timestamp"); // prevents errors when timestamp entered in milliseconds
        uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
        Lock storage userLock = locks[_lpToken][lockID];
        require(
            lockID == _lockID && userLock.owner == msg.sender,
            "relock::Lock mismatch"
        ); // ensures correct lock is affected
        require(userLock.unlockDate < _unlock_date, "relock::Invalid date");

        // check holding NFT of schema
        if (userLock.schemaId > 0) {
            require(
                signataRight.holdsTokenOfSchema(msg.sender, userLock.schemaId),
                "relock::Sender does not hold NFT of schema"
            );
        }

        userLock.amount = userLock.amount;
        userLock.unlockDate = _unlock_date;

        emit Relocked(_lockID, _unlock_date);
    }

    /**
     * @notice withdraw a specified amount from a lock. _index and _lockID ensure the correct lock is changed
     * this prevents errors when a user performs multiple tx per block possibly with varying gas prices
     */
    function withdraw(
        address _lpToken,
        uint256 _index,
        uint256 _lockID,
        uint256 _amount
    ) external nonReentrant {
        require(_amount > 0, "withdraw::Amount needs to be greater than 0");
        uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
        Lock storage userLock = locks[_lpToken][lockID];
        require(
            lockID == _lockID && userLock.owner == msg.sender,
            "withdraw::Lock mismatch"
        ); // ensures correct lock is affected
        require(userLock.unlockDate < block.timestamp, "withdraw::Lock not expired");
        userLock.amount = userLock.amount.sub(_amount);

        // check holding NFT of schema
        if (userLock.schemaId > 0) {
            require(
                signataRight.holdsTokenOfSchema(msg.sender, userLock.schemaId),
                "withdraw::Sender does not hold NFT of schema"
            );
        }

        // clean user storage
        if (userLock.amount == 0) {
            uint256[] storage userLocks = users[msg.sender].locksForToken[
                _lpToken
            ];
            userLocks[_index] = userLocks[userLocks.length - 1];
            userLocks.pop();
            if (userLocks.length == 0) {
                users[msg.sender].lockedTokens.remove(_lpToken);
            }
        }

        SafeERC20.safeTransfer(IERC20(_lpToken), msg.sender, _amount);
        emit Withdrawn(_lpToken, _amount);
    }

    /**
     * @notice increase the amount of tokens per a specific lock, this is preferable to creating a new lock, less fees, and faster loading on our live block explorer
     */
    function incrementLock(
        address _lpToken,
        uint256 _index,
        uint256 _lockID,
        uint256 _amount
    ) external nonReentrant {
        require(_amount > 0, "incrementLock::Amount needs to be greater than 0");
        uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
        Lock storage userLock = locks[_lpToken][lockID];
        require(
            lockID == _lockID && userLock.owner == msg.sender,
            "incrementLock::Lock mismatch"
        ); // ensures correct lock is affected

        // check holding NFT of schema
        if (userLock.schemaId > 0) {
            require(
                signataRight.holdsTokenOfSchema(msg.sender, userLock.schemaId),
                "incrementLock::Sender does not hold NFT of schema"
            );
        }

        SafeERC20.safeTransferFrom(
            IERC20(_lpToken),
            address(msg.sender),
            address(this),
            _amount
        );

        userLock.amount = userLock.amount.add(_amount);
        emit Deposited(
            _lpToken,
            msg.sender,
            _amount,
            userLock.lockDate,
            userLock.unlockDate,
            userLock.schemaId
        );
    }

    /**
     * @notice split a lock into two seperate locks, useful when a lock is about to expire and youd like to relock a portion
     * and withdraw a smaller portion
     */
    function splitLock(
        address _lpToken,
        uint256 _index,
        uint256 _lockID,
        uint256 _amount
    ) external payable nonReentrant {
        require(_amount > 0, "splitLock::Amount needs to be greater than 0");
        uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
        Lock storage userLock = locks[_lpToken][lockID];
        require(
            lockID == _lockID && userLock.owner == msg.sender,
            "splitLock::Lock Mismatch"
        ); // ensures correct lock is affected

        // check holding NFT of schema
        if (userLock.schemaId > 0) {
            require(
                signataRight.holdsTokenOfSchema(msg.sender, userLock.schemaId),
                "splitLock::Sender does not hold NFT of schema"
            );
        }

        userLock.amount = userLock.amount.sub(_amount);

        Lock memory lock;
        lock.lockDate = userLock.lockDate;
        lock.amount = _amount;
        lock.initialAmount = _amount;
        lock.unlockDate = userLock.unlockDate;
        lock.lockID = locks[_lpToken].length;
        lock.owner = msg.sender;

        // record the lock for the univ2pair
        locks[_lpToken].push(lock);

        // record the lock for the user
        UserInfo storage user = users[msg.sender];
        uint256[] storage user_locks = user.locksForToken[_lpToken];
        user_locks.push(lock.lockID);

        emit LockSplit(_lockID, _amount);
    }

    /**
     * @notice transfer a lock to a new owner
     */
    function transferLockOwnership(
        address _lpToken,
        uint256 _index,
        uint256 _lockID,
        address payable _newOwner
    ) external {
        require(msg.sender != _newOwner, "transferLockOwnership::Cannot transfer to self");
        uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
        Lock storage lock = locks[_lpToken][lockID];
        require(
            lockID == _lockID && lock.owner == msg.sender,
            "transferLockOwnership::Lock Mismatch"
        ); // ensures correct lock is affected

        // check holding NFT of schema
        if (lock.schemaId > 0) {
            require(
                signataRight.holdsTokenOfSchema(
                    _newOwner,
                    lock.schemaId
                ),
                "transferLockOwnership::New owner does not hold NFT of schema"
            );
        }

        // record the lock for the new Owner
        UserInfo storage user = users[_newOwner];
        user.lockedTokens.add(_lpToken);
        uint256[] storage user_locks = user.locksForToken[_lpToken];
        user_locks.push(lock.lockID);

        // remove the lock from the old owner
        uint256[] storage userLocks = users[msg.sender].locksForToken[_lpToken];
        userLocks[_index] = userLocks[userLocks.length - 1];
        userLocks.pop();
        if (userLocks.length == 0) {
            users[msg.sender].lockedTokens.remove(_lpToken);
        }
        lock.owner = _newOwner;

        emit LockTransferred(msg.sender, _newOwner);
    }

    function getNumLocksForToken(address _lpToken)
        external
        view
        returns (uint256)
    {
        return locks[_lpToken].length;
    }

    function getNumLockedTokens() external view returns (uint256) {
        return lockedTokens.length();
    }

    function getLockedTokenAtIndex(uint256 _index)
        external
        view
        returns (address)
    {
        return lockedTokens.at(_index);
    }

    // user functions
    function getUserNumLockedTokens(address _user)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = users[_user];
        return user.lockedTokens.length();
    }

    function getUserLockedTokenAtIndex(address _user, uint256 _index)
        external
        view
        returns (address)
    {
        UserInfo storage user = users[_user];
        return user.lockedTokens.at(_index);
    }

    function getUserNumLocksForToken(address _user, address _lpToken)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = users[_user];
        return user.locksForToken[_lpToken].length;
    }

    function getUserLockForTokenAtIndex(
        address _user,
        address _lpToken,
        uint256 _index
    )
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            address
        )
    {
        uint256 lockID = users[_user].locksForToken[_lpToken][_index];
        Lock storage lock = locks[_lpToken][lockID];
        return (
            lock.lockDate,
            lock.amount,
            lock.initialAmount,
            lock.unlockDate,
            lock.lockID,
            lock.schemaId,
            lock.owner
        );
    }

    function updateSignataRight(address _signataRight) public onlyOwner {
        signataRight = ISignataRight(_signataRight);
        emit SignataRightUpdated(_signataRight);
    }
}
