//SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

interface ICommunityFactory {
    function getCommunities() external view returns (address[] memory);

    function monthlyCost() external view returns (uint256);

    function subscriptions(address _communityWallet) external view returns (uint256);

    function containsCommunity(address _communityWallet) external view returns (bool);

    function addCommunity(address _communityWallet) external returns (bool);

    function communityPerWallet(address _communityWallet) external view returns(address);

    function isVerifiedMember(address _communityWallet, address _addr) external view returns(bool);

    function pushTask(address _communityWallet, uint256 _taskID) external;

    function pushProposal(address _communityWallet, uint256 _proposalID) external;

    function getParticipationThreshold(address _comToken) external view returns(uint256);

    function deleteMember(address _mainToken, address _member) external;
}
