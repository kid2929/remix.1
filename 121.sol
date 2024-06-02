// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenVesting is Ownable {
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 startTime;
        uint256 duration;
        uint256 claimedAmount;
    }

    struct Organization {
        string name;
        ERC20 token;
        address admin;
    }

    mapping(address => Organization) public organizations;
    mapping(address => mapping(address => VestingSchedule)) public vestingSchedules;
    mapping(address => mapping(address => bool)) public whitelisted;
    mapping(address => bool) public isOrganizationRegistered;

    event OrganizationRegistered(address indexed orgAddress, string name, address tokenAddress, address admin);
    event StakeholderAdded(address indexed orgAddress, address indexed stakeholder, uint256 totalAmount, uint256 startTime, uint256 duration);
    event TokensClaimed(address indexed orgAddress, address indexed beneficiary, uint256 amount);
    event AddressWhitelisted(address indexed orgAddress, address indexed stakeholder);
    event AddressRemovedFromWhitelist(address indexed orgAddress, address indexed stakeholder);

    modifier onlyOrgAdmin(address orgAddress) {
        require(msg.sender == organizations[orgAddress].admin, "Not organization admin");
        _;
    }

    constructor(address initialOwner) Ownable(initialOwner) {}

    function registerOrganization(string memory name, address tokenAddress) external {
        require(!isOrganizationRegistered[msg.sender], "Organization already registered");
        organizations[msg.sender] = Organization({
            name: name,
            token: ERC20(tokenAddress),
            admin: msg.sender
        });
        isOrganizationRegistered[msg.sender] = true;

        emit OrganizationRegistered(msg.sender, name, tokenAddress, msg.sender);
    }

    function addStakeholder(address orgAddress, address stakeholder, uint256 totalAmount, uint256 startTime, uint256 duration) external onlyOrgAdmin(orgAddress) {
        require(!whitelisted[orgAddress][stakeholder], "Stakeholder already added");
        require(organizations[orgAddress].token.balanceOf(msg.sender) >= totalAmount, "Insufficient token balance");
        require(organizations[orgAddress].token.allowance(msg.sender, address(this)) >= totalAmount, "Token allowance too low");
        require(organizations[orgAddress].token.transferFrom(msg.sender, address(this), totalAmount), "Token transfer failed");

        vestingSchedules[orgAddress][stakeholder] = VestingSchedule({
            totalAmount: totalAmount,
            startTime: startTime,
            duration: duration,
            claimedAmount: 0
        });

        whitelisted[orgAddress][stakeholder] = true;

        emit StakeholderAdded(orgAddress, stakeholder, totalAmount, startTime, duration);
        emit AddressWhitelisted(orgAddress, stakeholder);
    }

    function whitelistAddress(address orgAddress, address stakeholder) external onlyOrgAdmin(orgAddress) {
        require(!whitelisted[orgAddress][stakeholder], "Address already whitelisted");
        whitelisted[orgAddress][stakeholder] = true;
        emit AddressWhitelisted(orgAddress, stakeholder);
    }

    function removeWhitelistAddress(address orgAddress, address stakeholder) external onlyOrgAdmin(orgAddress) {
        require(whitelisted[orgAddress][stakeholder], "Address not whitelisted");
        whitelisted[orgAddress][stakeholder] = false;
        emit AddressRemovedFromWhitelist(orgAddress, stakeholder);
    }

    function isWhitelisted(address orgAddress, address stakeholder) external view returns (bool) {
        return whitelisted[orgAddress][stakeholder];
    }

    function claimTokens(address orgAddress) external {
        require(whitelisted[orgAddress][msg.sender], "Not a whitelisted address");

        VestingSchedule storage schedule = vestingSchedules[orgAddress][msg.sender];
        require(block.timestamp >= schedule.startTime, "Vesting period not started");

        uint256 vestedAmount = _vestedAmount(schedule);
        uint256 claimableAmount = vestedAmount - schedule.claimedAmount;

        require(claimableAmount > 0, "No tokens to claim");

        schedule.claimedAmount += claimableAmount;
        require(organizations[orgAddress].token.transfer(msg.sender, claimableAmount), "Token transfer failed");

        emit TokensClaimed(orgAddress, msg.sender, claimableAmount);
    }

    function _vestedAmount(VestingSchedule memory schedule) internal view returns (uint256) {
        if (block.timestamp >= schedule.startTime + schedule.duration) {
            return schedule.totalAmount;
        } else {
            return (schedule.totalAmount * (block.timestamp - schedule.startTime)) / schedule.duration;
        }
    }
}
