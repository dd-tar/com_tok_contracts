// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./CommunityToken.sol";

    struct Community{
        address owner;
        address wallet;
        address mainToken;
        // List of Users-Members (?) mb we don't need it bc we only need the verification of tgID ???
        mapping(address => Member) members;
        mapping(uint256 => address) memberAddress;   // todo set True when creating a Member
        uint256 numberOfMembers; // increment when creating, decrement when burning members; NOT equal to Verified members
        uint256 numberOfVerifiedMembers; // increment when member.verify >= threshold, decrement when burning members

        uint256 verificationThreshold; // todo: 2 as a default
        uint256 joiningTokenThreshold;
        // todo:
        // verify threshold (default: 2 || admin)
        // voting threshold (default: ?? )
        // create proposal threshold
        // create task threshold
        // or one threshold for everything
        mapping(address => bool) memberVerified;
    }

    struct Member{
        address addr;
        uint256 tgID; // member.id
        address[] verified;
    }

contract CommunityFactory is Ownable, ReentrancyGuard {

    address backlogContract;
    address votingContract;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private communityPerWallet;
    mapping(address => uint256) public tokenToCommunity;

    Community[] communities;

    event MemberCreated(address _member, uint256 _tgID, address comToken, uint256 _comId);

    function createMember(uint256 _comId, uint256 _tgID) external {
        require(_comId < communities.length, "Community does not exist.");
        // only owner of community community tokens
        address comToken = communities[_comId].mainToken;
        require(IERC20(comToken).balanceOf(msg.sender) >= communities[_comId].joiningTokenThreshold,
            "You must have { joiningTokenThreshold } community tokens to join this community.");
        require(communities[_comId].members[msg.sender].addr == address(0),
            "You are already a member (address already exists)."); // will fail if there is no such member? DOES MEMBER NEED ANY INITIALIZATION???
        require(communities[_comId].memberAddress[_tgID] == address(0), "This tgID already exists.");

        communities[_comId].memberAddress[_tgID] = msg.sender;
        communities[_comId].members[msg.sender].addr = msg.sender;
        communities[_comId].members[msg.sender].tgID = _tgID;

        communities[_comId].numberOfMembers++;

        emit MemberCreated(msg.sender, _tgID, comToken, _comId);
    }

    function isMember(uint256 _comId, address _user) public view returns(bool){
        require(_comId < communities.length, "Community does not exist.");
        address token = communities[_comId].mainToken;
        if(IERC20(token).balanceOf(_user) < communities[_comId].joiningTokenThreshold)
            return false;
        return communities[_comId].members[_user].addr != address(0);
    }

    /*
    function changeMemberAddress(uint256 _comId, address _addr) external {
        // only this member
        require(communityExists(_comId), "Community does not exist.");
        //comm = communityPerWallet[_community];
        // check member exists
        require(communityPerWallet[_community].members[msg.sender].addr != address(0), "Member does not exist."); // will fail if there is no such member? MEMBER NEED ANY INITIALIZATION???

        communityPerWallet[_community].members[_addr] = communityPerWallet[_community].members[msg.sender];  // А ТУТ ССЫЛКА ИЛИ ЗНАЧЕНИЕ СОХРАНЯЕТСЯ ???
        communityPerWallet[_community].members[_addr].addr = _addr;
        delete communityPerWallet[_community].members[msg.sender];  // обнулить member по старому адресу // я не могу удалить структуру, содержащую маппинг!!!!!!!!!!!!
    }
    */

    function didSenderVerifyMember(
        uint256 _comId,
        address _member,
        address _verifier
    ) private view returns (bool verified){
        for(uint i = 0; i < communities[_comId].members[_member].verified.length; i++) // HERE
            if (communities[_comId].members[_member].verified[i] == _verifier)
                return true;
        return false;
    }
// todo: memberVerified event

    event VerificationAccepted(uint256 comId, uint256 senderId, uint256 memberId);
    event MemberVerified(uint256 comId, uint256 memberId);

    function verifyMember(uint256 _comId, uint256 _tgId) external {
        address member = getMemberAddress(_comId, _tgId);
        require(isMember(_comId, member), "There's no such member.");
        uint256 userBalance = IERC20(getMainCommunityToken(_comId)).balanceOf(member);
        require(userBalance >= communities[_comId].joiningTokenThreshold, "User has not enough community tokens.");
        require(msg.sender != member, "Can't verify yourself.");

        Community storage comm = communities[_comId];
        // check sender & member exist
        require(comm.members[member].addr != address(0), "Member does not exist.");
        require(isVerifiedMember(_comId, msg.sender), "Sender is not a Verified member.");
        // check that sender didn't vote before
        require(!didSenderVerifyMember(_comId, member, msg.sender), "Sender has already verified this user."); // todo *
        // check that member has less than threshold verifications
        require(!comm.memberVerified[member], "Member already verified.");

        communities[_comId].members[member].verified.push(msg.sender);

        uint256 senderTg = communities[_comId].members[msg.sender].tgID;

        emit VerificationAccepted(_comId, senderTg, _tgId);

        if (communities[_comId].members[member].verified.length == comm.verificationThreshold){
            communities[_comId].memberVerified[member] = true;
            communities[_comId].numberOfVerifiedMembers++;
            delete comm.members[member].verified;
            emit MemberVerified(_comId, _tgId);
        }
    }

    event MemberDeleted(uint256 tgId, address _member, address comToken, uint256 _comId);

    function deleteMember(
        address _mainToken,
        address _member
    ) public returns(bool){
        uint256 comId = tokenToCommunity[_mainToken];
        require(tokenToCommunity[_mainToken]!=0 || communities[0].mainToken == _mainToken, "Community doesn't exist");
        require(msg.sender == communities[comId].mainToken, "Only for community token contract.");

        if(communities[comId].members[_member].addr == address(0))
            return false;

        uint256 tgId = communities[comId].members[_member].tgID;

        communities[comId].memberVerified[_member] = false;
        communities[comId].memberAddress[tgId] = address(0);
        delete communities[comId].members[_member];

        emit MemberDeleted(tgId, _member, _mainToken, comId);
        return true;
    }

    function changeVerificationThreshold(uint256 _comId, uint256 _threshold) external {
        // не больше 20 человек из-за цикла в alreadyVerified
        require(_threshold <= 20, "Threshold must be less than 20.");
        require(_comId < communities.length, "Community does not exist.");
        // default: 1
        require(_threshold <= communities[_comId].numberOfVerifiedMembers, "Not enough verified members");
        require(msg.sender == communities[_comId].owner, "Only community owner can change threshold.");

        communities[_comId].verificationThreshold = _threshold;
    }

    function changeJoiningTokenThreshold(uint256 _comId, uint256 _threshold) external {
        require(_comId < communities.length, "Community does not exist.");
        // default: 1e18
        require(msg.sender == communities[_comId].owner, "Only community owner can change threshold.");

        communities[_comId].joiningTokenThreshold = _threshold;
    }

    function isVerifiedMember(uint256 _comId, address _user) public view returns(bool isVerified){
        //require(isMember(_comId,_user), "Is not even a member.");
        if(!isMember(_comId,_user))
            return false;

        return communities[_comId].memberVerified[_user];
    }

    function initializeFactory(address _backlog, address _voting) external onlyOwner {
        backlogContract = _backlog;
        votingContract = _voting;
    }

    function changeComOwner(uint256 comId, address newOwner) external{
        require(newOwner != address(0), "Zero address can't be an owner");
        require(comId < communities.length, "Community does not exist.");
        require(communities[comId].owner == msg.sender, "Sender is not an owner.");

        communities[comId].owner = newOwner;
    }

    /*function pushTask(address _community, uint256 _taskID) external{
        // check the task or that it was created on Backlog contract
        require(msg.sender == backlogContract, "Only for backlog contract.");

        communityPerWallet[_community].tasks.push(_taskID);
    }

    function pushProposal(address _community, uint256 _proposalID) external{
        // check the proposal or that it was created on Backlog contract
        require(msg.sender == votingContract, "Only for voting contract.");

        communityPerWallet[_community].proposals.push(_proposalID);
    }*/

    event TokenCreated(uint256 comId, address token);
    event CommunityCreated(uint256 comId, address comWallet, address comToken, uint256 creatorId, address creatorAddress);

    // todo create community when creating token / IMPORTING token / creating task / creating voting proposal

    function createCommunity(
        address _wallet,
        address _mainToken,
        uint256 creatorTgID)
    public
    returns(uint256 comId){
        // todo require
        require(!communityPerWallet.contains(_wallet), "Community already exists.");

        uint256 id = communities.length;
        communities.push();
        Community storage newCom = communities[id];

        newCom.owner = msg.sender; // todo check if it will work as expected (call from other func/contract)
        newCom.wallet = _wallet;
        newCom.mainToken = _mainToken;
        newCom.verificationThreshold = 1;
        newCom.joiningTokenThreshold = 1e18;
        newCom.numberOfVerifiedMembers = 1;
        newCom.numberOfMembers = 1;

        newCom.memberVerified[msg.sender] = true;
        newCom.memberVerified[_wallet] = true;

        Member storage creator = newCom.members[msg.sender];
        creator.tgID = creatorTgID;
        creator.addr = msg.sender;
        //creator.verified.push(msg.sender);

        communities[id].memberAddress[creatorTgID] = msg.sender;

        communityPerWallet.add(_wallet);

        tokenToCommunity[_mainToken] = id;

        emit CommunityCreated(id, _wallet, _mainToken, creatorTgID, msg.sender);

        return id;
    }

    function CreateNewToken(
        string calldata _name,
        string calldata _symbol,
        uint128 _startPrice, // in wei
        uint256 _comId
    ) public
    returns(address tokenAddr){
        require(_comId < communities.length, "Community doesn't exist.");
        require(msg.sender == communities[_comId].owner || msg.sender == communities[_comId].wallet,
            "Only for community wallet or owner.");
        // TODO
        address currentToken = communities[_comId].mainToken;
        tokenToCommunity[currentToken] = 0;

        address communityWallet = communities[_comId].wallet;
        CommunityToken ct = new CommunityToken(_name, _symbol, _startPrice, communityWallet, msg.sender);
        address addr = address(ct);
        communities[_comId].mainToken = addr;
        tokenToCommunity[addr] = _comId;

        emit TokenCreated(_comId, addr);

        return addr;
    }

    function createCommunityWithToken(
        string calldata _name,
        string calldata _symbol,
        uint128 _startPrice, // in wei
        address _communityWallet,
        uint256 creatorTgID
    )
    external
    nonReentrant
    returns (address tokenAddress) {
        require(!communityPerWallet.contains(_communityWallet), "Community with this wallet already exists.");

        CommunityToken ct = new CommunityToken(_name, _symbol, _startPrice, _communityWallet, msg.sender);
        address addr = address(ct);

        uint256 comId = createCommunity(_communityWallet, addr, creatorTgID);
        tokenToCommunity[addr] = comId;

        emit TokenCreated(comId, addr);
        return addr;
    }

    function changeCommunityToken() public{
        // TODO only owner, check com exists
    }

    /*----view functions---------------------------------*/

    // also getMemberAddress -> address(0) if !exist
    function getMemberAddress(uint256 _comId, uint256 _tgId) public view returns(address){
        require(_comId < communities.length, "Community doesn't exist.");
        return communities[_comId].memberAddress[_tgId];
    }

    function getMemberTgId(uint256 _comId, address _member)public view returns(uint256){
        require(_comId < communities.length, "Community doesn't exist.");
        require(isMember(_comId, _member),"Member doesn't exist");

        return communities[_comId].members[_member].tgID;
    }

    function communityExists(address _com_tok) public view returns(bool){
        return tokenToCommunity[_com_tok] != 0 || communities[0].mainToken == _com_tok;
    }

    function getComIdByToken(address _com_tok) public view returns(uint256){
        return tokenToCommunity[_com_tok];
    }

    function getParticipationThreshold(address _comToken) public view returns(uint256){
        require(tokenToCommunity[_comToken] != 0 || communities[0].mainToken==_comToken, "Community doesn't exists.");
        uint256 comId = tokenToCommunity[_comToken];

        return communities[comId].joiningTokenThreshold;
    }

    // todo check view functions after changes
    function isComOwner(uint256 _comId, address _user) public view returns(bool){
        require(_comId < communities.length, "Community doesn't exists.");
        return _user == communities[_comId].owner;
    }

    function communityAt(uint256 _i) public view returns (address) {
        if(_i >= communities.length)
            return address(0);
        return communities[_i].wallet;
    }

    function getMainCommunityToken(uint256 _comId) public view returns (address){
        if(_comId >= communities.length)
            return address(0);
        return communities[_comId].mainToken;
    }

    function containsCommunity(address _communityWallet) external view returns (bool) {
        return communityPerWallet.contains(_communityWallet);
    }

    function numberOfCommunities() external view returns (uint256) {
        return communities.length;
    }

    // todo: pagination
    function getCommunities() external view returns (address[] memory) {
        uint256 communitiesLength = communityPerWallet.length();

        if (communitiesLength == 0) {
            return new address[](0);
        } else {
            address[] memory communitiesArray = new address[](communitiesLength);

            for (uint256 i = 0; i < communitiesLength; i++) {
                communitiesArray[i] = communityAt(i);
            }
            return communitiesArray;
        }
    }
}