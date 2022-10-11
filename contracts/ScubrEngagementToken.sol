// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/TokenTimelock.sol";

contract ScubrEngagementToken is ERC20, ERC20Burnable, Pausable, AccessControl {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // amount of tokens for reserve pool (10%)
    uint256 public reservePoolAmount;

    // amount of tokens for engagement awards (40%)
    uint256 public engagementAwardsAmount;

    // amount of tokens for staking awards (4%)
    uint256 public stakingAwardsAmount;

    // amount of tokens for ICO (20%)
    uint256 public icoAmount;

    // staking timelock mapping
    mapping(address => TokenTimelock) public stakingTimelocks;



    constructor() ERC20("Scubr Engagement Token", "SET") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        uint256 initialSupply = 100000000 * 10**18;

        reservePoolAmount = initialSupply * 10 / 100;
        engagementAwardsAmount = initialSupply * 40 / 100;
        stakingAwardsAmount = initialSupply * 4 / 100;
        icoAmount = initialSupply * 20 / 100;

        // store the reservePoolAmount, engagementAwardsAmount, stakingAwardsAmount, icoAmount in the contract itself and the rest to the owner
        _mint(msg.sender, initialSupply - reservePoolAmount - engagementAwardsAmount - stakingAwardsAmount - icoAmount);
        _mint(address(this), reservePoolAmount + engagementAwardsAmount + stakingAwardsAmount + icoAmount);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // mint stakingAwardsAmount
    function mintStakingAwardsAmount(uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(address(this), amount);
        stakingAwardsAmount += amount;
    }

    // mint engagementAwardsAmount
    function mintEngagementTokens(uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(address(this), amount);
        engagementAwardsAmount += amount;
    }


    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    // send token from the contract deployer to a specified address
    function sendTokenFromDeployer(address _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _transfer(msg.sender, _to, _amount);
    }


    // send engagement awards to a specified address
    function sendEngagementAwards(address _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount <= engagementAwardsAmount, "ScubrEngagementToken: Not enough engagement awards");
        _transfer(address(this), _to, _amount);
        engagementAwardsAmount -= _amount;
    }


    // send from reserve pool to a specified address
    function sendFromReservePool(address _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_amount <= reservePoolAmount, "ScubrEngagementToken: Not enough reserve pool amount");
        _transfer(address(this), _to, _amount);
        reservePoolAmount -= _amount;
    }

    // function to handle ICO token distribution to investors (only admin can call this function)
    function distributeIcoTokens(address[] memory _investors, uint256[] memory _amounts) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_investors.length == _amounts.length, "ScubrEngagementToken: Investors and amounts length mismatch");
        // check if the total amount of tokens to be distributed is less than or equal to the icoAmount
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            totalAmount += _amounts[i];
        }
        require(totalAmount <= icoAmount, "ScubrEngagementToken: Total amount to be distributed is greater than icoAmount");

        // transfer tokens to investors
        for (uint256 i = 0; i < _investors.length; i++) {
            _transfer(address(this), _investors[i], _amounts[i]);
        }

        // update icoAmount
        icoAmount -= totalAmount;
    }

    // function to withdraw tokens from the contract to a specified address (only admin can call this function)
    function withdrawTokens(address _to, uint256 _amount) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _transfer(address(this), _to, _amount);
    }


    // use TokenTimelock to allow users to stake their tokens and release them to users along with staking reward/// @notice Explain to an end user what this does
    // staking periods are: 6 months, 12 months, 24 months.
    // rewards are: 2%, 4%, 8% respectively
    // users can get a reward of maximum 5% of the stakingAwardsAmount
     function stakeTokens(uint256 _amount, uint256 _stakingPeriod) public payable {
        require(_stakingPeriod == 6 || _stakingPeriod == 12 || _stakingPeriod == 24, "ScubrEngagementToken: staking period should be 6, 12 or 24 months");
        require(_amount <= balanceOf(msg.sender), "ScubrEngagementToken: Amount to be staked is greater than balance");
        require(_amount <= stakingAwardsAmount, "ScubrEngagementToken: Amount to be staked is greater than staking awards amount");

        // dont allow users to stake if they already have a staking timelock
        require(stakingTimelocks[msg.sender] == TokenTimelock(address(0)), "ScubrEngagementToken: User already has a staking timelock");

        // calculate reward
        // rewards are: 2%, 4%, 8% respectively
        uint256 reward = 0;
        if (_stakingPeriod == 6) {
            reward = _amount * 2 / 100;
        } else if (_stakingPeriod == 12) {
            reward = _amount * 4 / 100;
        } else if (_stakingPeriod == 24) {
            reward = _amount * 8 / 100;
        }

        require(reward <= stakingAwardsAmount * 5 / 100, "ScubrEngagementToken: Reward to be staked should be less than 5% of the staking awards amount");

        // transfer tokens to this contract
        _transfer(msg.sender, address(this), _amount);


        // create a new TokenTimelock contract
        TokenTimelock timelock = new TokenTimelock(this, msg.sender, block.timestamp + _stakingPeriod * 30 days);

        // store the timelock contract address in the stakingTimelocks mapping
        stakingTimelocks[msg.sender] = timelock;

        // transfer tokens & reward to the timelock contract
        _transfer(address(this), address(timelock), _amount + reward);

        // update stakingAwardsAmount
        stakingAwardsAmount -= reward;
    }

    // function to allow users to withdraw their staked tokens and rewards after the staking period is over
    function withdrawStakedTokens() public {
        // get the timelock contract address for the user
        TokenTimelock timelock = stakingTimelocks[msg.sender];

        // check if the staking period is over
        require(block.timestamp >= timelock.releaseTime(), "ScubrEngagementToken: Staking period is not over");

        // transfer tokens to the user
        timelock.release();

        // delete the timelock contract address from the stakingTimelocks mapping
        delete stakingTimelocks[msg.sender];

    }

}