// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract Staking {
    address public _owner;          //address of contract owner
    IERC20 public _stakingtoken;    // token that users can stake
    IERC20 public _rewardtoken;     // token that is handed out as reward
    uint256 public _rewardrate;     // amount of rewards that are issued per block
    uint256 public _rewardduration; // amount of blocks that staking will be active for
    uint256 public _endrewards;     // block number where the rewards end
    struct Row {                    // struct with block.number and amount to keep track of transactions and balances
        uint256 timestamp;
        uint256 deposited;
    }
    Row[] public balance;                         // list of the contracts balances marked with blocknumber and balance
    mapping(address => Row) public deposits;      // mapping of user address to deposited amount with timestamp
    mapping(address => uint256) public claimable; // mapping of user address to amount of reward tokens they can claim

    constructor(address stakingtoken) {
        _owner = msg.sender;
        _stakingtoken = IERC20(stakingtoken);
    }

    event updateClaim(address _for, uint256 amount, uint256 timestamp);

    function fund(address rewardtoken, uint256 amount, uint256 duration) public {
        require(msg.sender == _owner, "Only the owner can fund the contract");
        require(amount > 0, "Cannot fund with 0 tokens");
        require(duration > 0, "Cannot set reward duration to 0");

        // transfer tokens to contract
        _rewardtoken = IERC20(rewardtoken);
        _rewardtoken.transferFrom(msg.sender, address(this), amount);

        // set contract parameters
        _rewardrate = amount / duration;
        _rewardduration = duration;
        _endrewards = duration + block.number;
        Row memory row = Row(block.number, 0);
        balance.push(row);
    }

    function stake(uint256 amount) public {
        require(amount > 0);
        require(_stakingtoken.balanceOf(msg.sender) >= amount, "Cannot stake more tokens than you own");

        // transfer tokens into contract
        _stakingtoken.transferFrom(msg.sender, address(this), amount);

        // check if user has already deposited tokens
        if (deposits[msg.sender].deposited > 0) {
            uint256 oldamount = deposits[msg.sender].deposited;
            _updateClaimable(msg.sender, oldamount, deposits[msg.sender].timestamp);
            delete deposits[msg.sender]; // delete immediately to avoid datarace problems
            amount += oldamount; // user new balance is old balance + deposited amount
        }
        // save user new balance together with block number
        Row memory row = Row(block.number, amount);
        deposits[msg.sender] = row;
        _updateBalance(amount, true);
    }

    function withdraw(uint256 amount) public {
        uint256 oldbalance = deposits[msg.sender].deposited;
        uint256 oldtimestamp = deposits[msg.sender].timestamp;
        require(oldbalance >= amount, "Cannot withdraw more tokens than you deposited");

        // calculate user's new balance after withdrawal
        uint256 newbalance = oldbalance - amount;

        // calculate their accrued rewards during staked period
        _updateClaimable(msg.sender, oldbalance, oldtimestamp);
        Row memory row = Row(block.number, newbalance);
        deposits[msg.sender] = row;

        // set new balance before transfer to avoid datarace problems
        _updateBalance(amount, false);

        // transfer staking tokens to user
        _stakingtoken.transfer(msg.sender, amount);
    }

    function claim() public {
        // update claimable balance
        uint256 oldbalance = deposits[msg.sender].deposited;
        uint256 oldtimestamp = deposits[msg.sender].timestamp;
        deposits[msg.sender].timestamp = block.timestamp; // avoid datarace problems by resetting timestamp first
        _updateClaimable(msg.sender, oldbalance, oldtimestamp);

        // transfer claimable balance to user
        uint256 oldclaimable = claimable[msg.sender];
        claimable[msg.sender] = 0; // avoid datarace problems by setting to 0 before transfer
        _rewardtoken.transfer(msg.sender, oldclaimable);
    }

    function getUserDepositTime(address user)  public view returns (uint256) {
        return deposits[user].timestamp;
    }

    function getUserDepositAmount(address user)  public view returns (uint256) {
        return deposits[user].deposited;
    }

    function getUserClaimableBalance(address user) public view returns (uint256) {
        return claimable[user];
    }

    function _updateClaimable(address _for, uint256 amount, uint256 timestamp) private {
        emit updateClaim(_for, amount, timestamp);
        uint256 newclaimable = claimable[_for];
        uint256 index = 1;
        Row memory row = balance[balance.length - index];
        uint256 prevbalance = row.deposited;
        uint256 prevtimestamp = block.number-1;

        // iterate backwards over list until we reach the block where the user deposited
        if (index < balance.length) {
            while (prevtimestamp > timestamp) {
                Row memory currentbalance = balance[balance.length - index];
                if (_checkNotZero(currentbalance.deposited, _rewardrate, prevtimestamp - row.timestamp)){
                    newclaimable += amount / currentbalance.deposited * _rewardrate * (prevtimestamp - row.timestamp);
                    prevbalance = currentbalance.deposited;
                    prevtimestamp = currentbalance.timestamp;
                    index -= 1; // should be += ??
                }
                else {
                    break;
                }
            }
        }
        claimable[_for] = newclaimable;
    }

    function _checkNotZero(uint256 deposited, uint256 rewardrate, uint256 timedifference) private pure returns (bool) {
        if (deposited <= 0) {
            return false;
        }
        else if (rewardrate <= 0) {
            return false;
        }
        else if (timedifference <= 0) {
            return false;
        }
        else {
            return true;
        }
    }

    function _updateBalance(uint256 amount, bool isDeposit) private {
        Row memory current = balance[balance.length - 1];
        if (isDeposit == true) {
            Row memory newbalance = Row(block.number, current.deposited + amount);
            _pushbalance(current.timestamp, newbalance);
        }
        else {
            Row memory newbalance = Row(block.number, current.deposited - amount);
            _pushbalance(current.timestamp, newbalance);
        }
    }

    function _pushbalance(uint256 timestamp, Row memory newbalance) private {
        if (timestamp == block.number) {
            balance[balance.length - 1] = newbalance;
        }
        else {
            balance.push(newbalance);
        }
    }

}
