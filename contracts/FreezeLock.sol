// SPDX-License-Identifier: MIT

pragma solidity = 0.8.19;

import "@openzeppelin/contracts@4.9.0/utils/Address.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.0/token/ERC20/utils/SafeERC20.sol";

/**
* Gyrowin FreezeLock Contract
* https://gyro.win
*/
interface GyrowinInternal {
    // GyrowinContract
    function subtractCirculatingSupply(address contractAddr, uint256 amount) external;
    function addCirculatingSupply(address contractAddr, uint256 amount) external;
}

enum Status {
    Claimed,
    Unclaimed
}

struct FreezeLock {
    uint256 unlockAmount;
    uint256 freezeStartTime;
    uint256 freezeEndTime;
    Status freezeStatus;
    string description;
}

contract GyrowinFreezeLock {
    using SafeERC20 for IERC20;

    modifier onlyOwner() {
        require(_owner == _msgSender(), "GW: !owner");
        _;
    }

    modifier onlyOperator() {
        require(_operator == _msgSender(), "GW: !operator");
        _;
    }

    /// @notice operator of the contract
    /// @dev should be multisig address
    address private _operator;

    /// @notice owner of the contract
    /// @dev should be multisig address
    address private _owner;

    /// @notice address of the gyrowin token
    address public constant GYROWIN_ADDRESS = 0x77774A06271d6A305CAccDBc06f847DEF05c7777;

    /// @notice time period of the freeze lock
    /// @dev set it to 7 days and is not reversible
    uint256 public constant FREEZE_DURATION = 604800; // time period of the freeze lock
    uint256 requestId;

    uint256 public nextRequestId;

    /// @notice request id should always be unique
    /// @dev request Id => freezeLock
    mapping(uint256 => FreezeLock) freezeRequests;

    /// @notice total gyrowin locked in the contract
    uint256 public locked;

    receive() payable external {}

    event LockTokens(uint amount, uint lockTime, address lockedBy);
    event Withdrawal(uint amount, uint withdrawalTime, string description);
    event requestWithdrawl(uint indexed id, uint amount, uint freezeStart, uint freezeEnd, string description);


    /**
     * @notice Construct a new FreezeLock
    */
    bool private _initialize;
    function initialize(address owner) external {
        require(owner == address(0x05803c32E393765a204e22fCF560421729cbCA42), "GW: !owner");
        require(_initialize == false, "GW: initialized");
        _owner = owner;
        _operator = owner;
        _initialize = true;
    }


    /**
     * @notice Locked tokens in the contract with freeze lock rules
     * @param _amount amount of the token to be locked in the contract
     */
    function freezelockToken(uint256 _amount) external onlyOperator() {
        require(_amount > 0, "GW: zero amount!");
        IERC20(GYROWIN_ADDRESS).safeTransferFrom(_msgSender(), address(this), _amount);

        GyrowinInternal(GYROWIN_ADDRESS).subtractCirculatingSupply(address(this), _amount);

        locked += _amount;

        emit LockTokens(_amount, block.timestamp, _msgSender());
    }

    /**
     * @notice Request the amount of tokens before its unlocked
     * @param _amount request amount for unlock
     */
    function requestWithdraw(uint256 _amount, string memory _description) external onlyOperator() {
        require(_amount <= locked, "GW: exceeds locked amount");

        freezeRequests[requestId].freezeStartTime = block.timestamp;
        freezeRequests[requestId].freezeEndTime =
            block.timestamp +
            FREEZE_DURATION;
        freezeRequests[requestId].unlockAmount = _amount;
        freezeRequests[requestId].freezeStatus = Status.Unclaimed;
        freezeRequests[requestId].description = _description;

        emit requestWithdrawl(
            requestId,
            _amount,
            freezeRequests[requestId].freezeStartTime,
            freezeRequests[requestId].freezeEndTime,
            freezeRequests[requestId].description
        );

        requestId++;
        nextRequestId = requestId;
    }

    /**
     * @notice Withdraw the unlocked token amount after the freezing period
     * @param _requestId id for the unlocking request
     * @param receiver address of the accoun that receives the unlocked token
     */
    function withdraw(
        uint256 _requestId,
        address receiver
    ) public onlyOperator() {
        require(_requestId < nextRequestId, "GW: no request Id found");
        require(freezeRequests[_requestId].freezeEndTime < block.timestamp, "GW: freeze lock not over");
        require(freezeRequests[_requestId].freezeStatus == Status.Unclaimed, "GW: amount already claimed");

        emit Withdrawal(
            freezeRequests[_requestId].unlockAmount,
            block.timestamp,
            freezeRequests[_requestId].description
        );

        GyrowinInternal(GYROWIN_ADDRESS).addCirculatingSupply(address(this), freezeRequests[_requestId].unlockAmount);

        IERC20(GYROWIN_ADDRESS).safeTransfer(receiver, freezeRequests[_requestId].unlockAmount);

        locked -= freezeRequests[_requestId].unlockAmount;

        freezeRequests[_requestId].freezeStatus = Status.Claimed;
        freezeRequests[_requestId].unlockAmount = 0;
    }

    /**
     * @notice checks for the gyrowin token, that wasn't locked in the contract
     * @return amount that can be withdrawn
     */
    function withdrawableAmount() public view returns (uint256) {
        uint256 _withdrawableAmount = IERC20(GYROWIN_ADDRESS).balanceOf(address(this)) - locked;
        return _withdrawableAmount;
    }

    /**
     * @notice Check the information of the withdrawl request
     * @param _requestId id of the requested withdrawl
     * @return freezeStartTime time of the freeze lock request
     * @return freezeEndTime end time of the freeze lock
     * @return unlockAmount requestd amount to be unlocked
     * @return freezeStatus check if the token is clamimed after the 7 days freeze period
     */
    function viewWithdrawlRequest(
        uint _requestId
    ) public view returns (uint, uint, uint, Status) {
        return (
            freezeRequests[_requestId].freezeStartTime,
            freezeRequests[_requestId].freezeEndTime,
            freezeRequests[_requestId].unlockAmount,
            freezeRequests[_requestId].freezeStatus
        );
    }

    /**
     * @notice change the address of the contract owner address
     * @param owner  new owner of the contract
     */
    function changeOwner(address owner) external onlyOwner() {
        _owner = owner;
    }

    /**
     * @notice change the address of the contract operator address
     * @param operator new operator of the contract
     */
    function changeOperator(address operator) external onlyOwner() {
        _operator = operator;
    }

    /**
     * @return address of the owner
     */
    function isOwner() external view returns (address) {
        return _owner;
    }

    /**
     * @return address of the operator
     */
    function isOperator() external view returns (address) {
        return _operator;
    }

    /**
     * @return address of the msg sender
     */
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }


    /**
     * @notice Resuce chain native token that is sent by mistake to this contract
     * @param to addresss of the account that recives the native token
     * @param amount ammount of the token trapped
     */
    function rescueNative(address payable to, uint256 amount) external onlyOwner() {
        require(amount > 0, "GW: zero amount");
        require(to != address(0), "GW: can't be zero address");
        require(amount <= address(this).balance, "GW: insufficent balance");
        to.transfer(amount);
    }

    /**
     * @notice Resuce BEP20 tokens that are sent by mistake to this contract
     * @param token address of the token, that is trapped in the token
     * @param to addresss of the account that recives the native token
     * @param amount ammount of the token trapped
     * @dev Might have instances where someone would send gyrowin token to this address
     */
    function rescueBep20(address token, address to, uint256 amount) external payable onlyOwner() {
        require(amount > 0, "GW: zero amount");
        require(to != address(0), "GW: can't be zero address");
        // check if the token is gyrowin
        if (token == GYROWIN_ADDRESS) {
            require(amount <= withdrawableAmount(), "GW: exceeds unlocked tokens");
        } else {
            require(amount <= IERC20(token).balanceOf(address(this)), "GW: insufficent balance");
        }

        IERC20(token).safeTransfer(to, amount);
    }
}
