// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract Clip is Owned {
    address public immutable USDC;
    address public immutable TREASURY;

    // This is the unix timestamp of the next release
    uint256 public currentReleasePeriod;

    // This is the amount of ETH that each user has deposited in a release period
    mapping(address => mapping(uint256 => uint256)) public releasePeriodBalances;
    // This is the total amount of ETH that has been deposited in a release period
    mapping(uint256 => uint256) public releasePeriodRewards;

    error TooMuchEth();
    error ReleaseNotReady();

    constructor(address _treasury, address _usdc) Owned(msg.sender) {
        TREASURY = _treasury;
        USDC = _usdc;
        currentReleasePeriod = block.timestamp;
    }

    function depositEth() payable public {
        if (msg.value > 20 ether) revert TooMuchEth();

        // We can assume these won't overflow
        unchecked {
            // This tracks the user deposits for a period
            releasePeriodBalances[msg.sender][currentReleasePeriod] += msg.value;
            // This tracks the total deposits for a period
            releasePeriodRewards[currentReleasePeriod] += msg.value;
        }
    }

    /// @notice block.timestamp can be manipulated by validators, but outsiders
    /// @notice cannot use this function so we can assume good intentions from owner.
    /// @dev There is never any overlap or time between release periods.
    /// @dev We assume that the treasury has approved a 1000 USDC token transfer.
    /// @dev After this has been called deposits cannot be made for the last release period.
    function releaseRewards() public onlyOwner {
        if (block.timestamp < currentReleasePeriod + 7 days) revert ReleaseNotReady();

        // Overflow is only possible in like a million years
        unchecked {
            currentReleasePeriod += 7 days;
        }

        // 1000e6 is 1000 USDC with 6 decimals
        ERC20(USDC).transferFrom(TREASURY, address(this), 1000e6);
    }

    /// @dev if unsure of the correct release period, it can be calculated by taking the 
    /// @dev current release period and subtracting (7 days) until desired one is found
    /// @param releasePeriod The release period to claim rewards for
    /// @param reward amount of USDC claimed based on deposits
    function claimRewards(uint256 releasePeriod) public returns (uint256 reward) {
        // If the releasePeriod is not valid then these numbers will be zero
        // and calculateReward will revert on division by zero
        uint256 userDeposits = releasePeriodBalances[msg.sender][releasePeriod];
        uint256 totalDeposits = releasePeriodRewards[releasePeriod];

        // Calculate the amount of USDC to send to the user
        reward = calculateReward(userDeposits, totalDeposits);

        // Set the user's balance in the time period to 0
        releasePeriodBalances[msg.sender][releasePeriod] = 0;

        // Give the user the ETH that they deposited and their USDC reward
        payable(msg.sender).transfer(userDeposits);
        ERC20(USDC).transfer(msg.sender, reward);
    }

    /// @dev This is the users proportion of the reward that they get.
    /// @dev userDeposits is never greater than total deposits.
    function calculateReward(uint256 userDeposits, uint256 totalDeposits) internal pure returns (uint256) {
        // Calculate the amount of USDC to send to the user
        return (userDeposits * 1000e6) / totalDeposits;
    }

    /// @dev due to rounding with division of uints a little bit of dust can be left in the contract
    /// @return withdrawn amount of dust sent to the treasury
    function withdrawDust() public onlyOwner returns (uint withdrawn) {
        withdrawn = ERC20(USDC).balanceOf(address(this));
        ERC20(USDC).transfer(TREASURY, withdrawn);
    }

    receive() payable external {
        depositEth();
    }
}
