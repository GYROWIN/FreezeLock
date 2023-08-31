// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "hardhat/console.sol";

enum Status {
    Claimed,
    Unclaimed
}

struct FreezeLock {
    uint256 unlockAmount;
    uint256 freezeStartTime;
    uint256 freezeEndTime;
    Status freezeStatus;
}

contract Lock {
    using SafeERC20 for IERC20;

    modifier onlyOperator() {
        require(msg.sender == operator, "Not Operator");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /// @notice Total gyrowin locked in the contract
    uint256 public locked;

    address operator;

    /// @notice owner of the contract
    /// @dev should be multisig address
    address owner;

    /// @notice address of the gyrowin token
    address public gyrowinAddress;

    /// @notice time period of the freeze lock
    /// @dev set it to 7 days and is not reversible
    uint256 public constant FREEZE_DURATION = 604800; // time period of the freeze lock
    uint256 requestId;

    /// @notice request id should always be unique
    /// @dev request Id => freezeLock
    mapping(uint256 => FreezeLock) freezeRequests;

    event LockTokens(uint amount, uint lockTime);
    event Withdrawal(uint amount, uint withdrawalTime);
    event requestWithdrawl(uint amount, uint freezeStart, uint freezeEnd);

    constructor(address _tokenAddr, address _operator) payable {
        gyrowinAddress = _tokenAddr;
        operator = _operator;
        owner = (msg.sender);
    }

    /**
     * Locked tokens in the contract with freeze lock rules
     * @param _amount amount of the token to be locked in the contract
     */
    function lockToken(uint256 _amount) public onlyOperator {
        IERC20(gyrowinAddress).safeTransfer(address(this), _amount);

        locked += _amount;

        emit LockTokens(_amount, block.timestamp);
    }

    /**
     * Request the amount of tokens before its unlocked
     * @param _amount request amount for unlock
     */
    function requestWithdraw(uint256 _amount) public onlyOperator {
        require(_amount <= locked, "Exceeds locked amount");

        freezeRequests[requestId].freezeStartTime = block.timestamp;
        freezeRequests[requestId].freezeEndTime =
            block.timestamp +
            FREEZE_DURATION;
        freezeRequests[requestId].unlockAmount = _amount;
        freezeRequests[requestId].freezeStatus = Status.Unclaimed;

        emit requestWithdrawl(
            _amount,
            freezeRequests[requestId].freezeStartTime,
            freezeRequests[requestId].freezeEndTime
        );

        requestId++;
    }

    /**
     * Withdraw the unlocked token amount after the freezing period
     * @param _requestId id for the unlocking request
     * @param receiver address of the accoun that receives the unlocked token
     */
    function withdraw(
        uint256 _requestId,
        address receiver
    ) public onlyOperator {
        require(
            freezeRequests[_requestId].freezeStatus == Status.Unclaimed,
            "Amount already claimed"
        );
        require(
            freezeRequests[_requestId].freezeEndTime < block.timestamp,
            "Freeze lock not over"
        );

        emit Withdrawal(
            freezeRequests[_requestId].unlockAmount,
            block.timestamp
        );

        IERC20(gyrowinAddress).safeTransfer(
            receiver,
            freezeRequests[_requestId].unlockAmount
        );

        locked -= freezeRequests[_requestId].unlockAmount;

        freezeRequests[_requestId].freezeStatus = Status.Claimed;
        freezeRequests[_requestId].unlockAmount = 0;
    }

    /**
     * change the address of the contract owner address
     * @param _owner  new owner of the contract
     */
    function changeOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    /**
     * change the address of the contract operator address
     * @param _operator new operator of the contract
     */
    function changeOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    /**
     * Resuce chain native token that is sent by mistake to this contract
     * @param to addresss of the account that recives the native token
     * @param amount ammount of the token trapped
     */
    function rescueNative(address payable to, uint256 amount) public onlyOwner {
        require(amount <= address(this).balance, "Insufficent Balance");
        to.transfer(amount);
    }

    /**
     * Resuce BEP20 tokens that are sent by mistake to this contract
     * @param token address of the token, that is trapped in the token
     * @param to addresss of the account that recives the native token
     * @param amount ammount of the token trapped
     */
    function rescueBep20(
        address token,
        address to,
        uint256 amount
    ) public onlyOwner {
        require(token != gyrowinAddress, "Token locked");
        require(
            amount <= IERC20(token).balanceOf(address(this)),
            "Insufficent Balance"
        );

        IERC20(token).safeTransfer(to, amount);
    }
}
