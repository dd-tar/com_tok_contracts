//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./CommunityFactory.sol";

// TODO check
// import IERC20

    struct Proposal{
        address creator;
        // link for description of Proposal and options to vote for
        // for solutions of tasks it should be formed from Backlog.sol contract
        string proposalDescription;
        uint256 numberOfOptions; // ( 1, 2, ...  numberOfOptions)
        uint256 voteCount;
        mapping(uint256 => uint256) votes; // choice => numberOfVotes
        mapping(address => uint256) voted; // member => choice
        bool executed;
        uint256 deadline;

        uint256 max;
        uint256[] winningOptions;
    }

struct CommunityVoting{
    mapping(uint256 => Proposal) votings; // ids from 1
    uint256 numberOfVotings;

    address votingToken; // default: community token
    uint256 votingThreshold; // min number of people to vote; default: 1
}


contract Voting {

    CommunityFactory communityFactory;
    address backlogContract;

    mapping (uint256 => CommunityVoting) comVotings;

    modifier onlyVerifiedMember(uint256 _comId){
        require(communityFactory.isVerifiedMember(_comId, msg.sender) || msg.sender == backlogContract,
            "Sender is not verified community member.");
        _;
    }

    modifier hasVotingTokens(uint256 _comId){
        address token = communityFactory.getMainCommunityToken(_comId);
        uint256 userBalance = IERC20(token).balanceOf(msg.sender);
        require(userBalance >= communityFactory.getParticipationThreshold(token), "Sender has not enough voting tokens.");
        _;
    }

    uint256 proposalCount;

    constructor(address _communityFactory, address _backlog){
        communityFactory = CommunityFactory(_communityFactory);
        backlogContract = _backlog;
    }

    event ProposalCreated(
        address comToken,
        uint256 proposalId,
        uint256 creator,
        string proposal,
        uint256 numberOfOptions,
        uint256 deadline
    );

    event ProposalExecuted(
    address comToken,
    uint256 proposalId,
    uint256[] winningOptions
    );

    function createCommunityVotings(uint256 _comId, address _votingToken, uint256 _votingThreshold) private onlyVerifiedMember(_comId){
        CommunityVoting storage cv = comVotings[_comId];
        cv.votingThreshold = _votingThreshold;
        cv.votingToken = _votingToken;
    }

    function createProposal(
        uint256 _comId,
        string memory _proposal,
        uint256 _numberOfOptions,
        uint256 _deadline, // in hours
        address creator // backlog should give task creator
    ) public
    onlyVerifiedMember(_comId)
    hasVotingTokens(_comId)
    returns (uint256 votingID){
        require(msg.sender == creator || msg.sender == backlogContract, "Creator should match sender or backlog contract.");
        require(_numberOfOptions >= 2 || msg.sender == backlogContract && _numberOfOptions > 0,
            "Wrong number of voting options. Must be at least 2 options for proposals and 1 solution for tasks.");
        require(_deadline > 0, "The deadline can't be in 0 hours");
        // todo any other requirements?
        address comToken = communityFactory.getMainCommunityToken(_comId);
        if(comVotings[_comId].numberOfVotings == 0)
            createCommunityVotings(_comId, comToken, 1);
        uint256 member_id = communityFactory.getMemberTgId(_comId, creator);
        uint256 prop_id = comVotings[_comId].numberOfVotings++; // ids from 1
        Proposal storage newProposal = comVotings[_comId].votings[prop_id];
        newProposal.creator = creator;
        newProposal.proposalDescription = _proposal;
        newProposal.numberOfOptions = _numberOfOptions;
        newProposal.deadline = block.timestamp + _deadline * 1 hours;
        //comVotings[_comId].votings[id] = newProposal;

        emit ProposalCreated(comToken, prop_id, member_id, newProposal.proposalDescription,
            newProposal.numberOfOptions, newProposal.deadline);
        return prop_id;
    }

    event MemberVoted(uint256 comId, uint256 proposalId, uint256 member);

    function vote(uint256 _comId, uint256 _propId, uint256 _choice /*, */)
    public
    onlyVerifiedMember(_comId)
    hasVotingTokens(_comId)
    {
        require(_propId <= comVotings[_comId].numberOfVotings || _propId > 0, "Proposal doesn't exist.");
        require(comVotings[_comId].votings[_propId].voted[msg.sender] == 0,"Sender voted already.");
        require(block.timestamp < comVotings[_comId].votings[_propId].deadline, "The deadline of voting has passed.");
        require((_choice <= comVotings[_comId].votings[_propId].numberOfOptions) && (_choice != 0), "There's no such choice.");
        require(!comVotings[_comId].votings[_propId].executed, "Already executed.");

        comVotings[_comId].votings[_propId].voted[msg.sender] = _choice;
        uint256 votesForOption = comVotings[_comId].votings[_propId].votes[_choice]++;
        comVotings[_comId].votings[_propId].voteCount++;

        // check search for max values
        if(votesForOption > comVotings[_comId].votings[_propId].max){
            comVotings[_comId].votings[_propId].max = votesForOption;
            delete comVotings[_comId].votings[_propId].winningOptions;
            comVotings[_comId].votings[_propId].winningOptions.push(_choice);
        }
        else if(votesForOption == comVotings[_comId].votings[_propId].max)
            comVotings[_comId].votings[_propId].winningOptions.push(_choice);

        uint256 member_id = communityFactory.getMemberTgId(_comId, msg.sender);

        emit MemberVoted(_comId, _propId, member_id);

    }

    function executeVoting(
        uint256 _comId,
        uint256 _proposalId
    ) public onlyVerifiedMember(_comId) returns (uint256[] memory){
        require(_proposalId <= comVotings[_comId].numberOfVotings, "Proposal doesn't exist.");
        require(block.timestamp >= comVotings[_comId].votings[_proposalId].deadline, "Voting deadline hasn't pass.");
        require(!comVotings[_comId].votings[_proposalId].executed, "Already executed.");
        // require Threshold of people reached
        require(comVotings[_comId].votings[_proposalId].voteCount >= comVotings[_comId].votingThreshold, "Not enough votes to execute. The threshold isn't reached.");

        comVotings[_comId].votings[_proposalId].executed = true;

        address comToken = communityFactory.getMainCommunityToken(_comId);

        emit ProposalExecuted(comToken, _proposalId, comVotings[_comId].votings[_proposalId].winningOptions);

        return comVotings[_comId].votings[_proposalId].winningOptions;
    }

    function changeVotingToken(uint256 _comId, address _newVotingToken) public onlyVerifiedMember(_comId){
        require(communityFactory.isComOwner(_comId, msg.sender), "Only for community owner.");
        require(_newVotingToken != address(0), "Voting token can't be zero address.");
        require(IERC20(_newVotingToken).balanceOf(msg.sender) != 0, "Should have balanceOf function."); //TODO Should have balanceOf function

        comVotings[_comId].votingToken = _newVotingToken;
    }

    function changeVotingThreshold(uint256 _comId, uint256 _newThreshold) public onlyVerifiedMember(_comId) {
        require(communityFactory.isComOwner(_comId, msg.sender), "Only for community owner.");
        require(_newThreshold >= 2, "The threshold can't be less than 2.");
        comVotings[_comId].votingThreshold = _newThreshold;
    }

    function getVotingDescription(uint256 _comId, uint256 _propId) public view returns (string memory){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        require(_propId <= comVotings[_comId].numberOfVotings ,"Proposal doesn't exist.");
        return comVotings[_comId].votings[_propId].proposalDescription;
    }

    function getVotingDeadline(uint256 _comId, uint256 _propId) public view returns (uint256){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        require(_propId <= comVotings[_comId].numberOfVotings ,"Proposal doesn't exist.");
        return comVotings[_comId].votings[_propId].deadline;
    }

    function getVotingCreator(uint256 _comId, uint256 _propId) public view returns (uint256){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        require(_propId <= comVotings[_comId].numberOfVotings ,"Proposal doesn't exist.");
        address creatorAddress = comVotings[_comId].votings[_propId].creator;
        uint256 creatorId = communityFactory.getMemberTgId(_comId, creatorAddress);
        return creatorId;
    }

    function getVotingExecuted(uint256 _comId, uint256 _propId) public view returns (bool){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        require(_propId <= comVotings[_comId].numberOfVotings ,"Proposal doesn't exist.");
        return comVotings[_comId].votings[_propId].executed;
    }

    function getVotingNumberOfOptions(uint256 _comId, uint256 _propId) public view returns (uint256){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        require(_propId <= comVotings[_comId].numberOfVotings ,"Proposal doesn't exist.");
        return comVotings[_comId].votings[_propId].numberOfOptions;
    }

    function getVotingWinningOptions(uint256 _comId, uint256 _propId) public view returns (uint256[] memory){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        require(_propId <= comVotings[_comId].numberOfVotings,"Proposal doesn't exist.");
        if (!comVotings[_comId].votings[_propId].executed){
            uint256[] memory void;
            return void;
        }
        return comVotings[_comId].votings[_propId].winningOptions;
    }

    function getNumberOfVotings(uint256 _comId)public view returns (uint256){
        require(communityFactory.getMainCommunityToken(_comId) != address(0), "Community with such id doesn't exist");
        return comVotings[_comId].numberOfVotings;
    }


    /*
    function executeProposal(uint256 _proposalId) public {
        Proposal storage proposal = proposals[_proposalId];
        require(msg.sender == proposal.creator, "Only the proposal creator can execute this proposal.");
        require(proposal.voteCount >= (threshold1 / 2) + 1, "The proposal does not have enough votes to be executed.");
        require(!proposal.executed, "The proposal has already been executed.");
        // todo Execute the proposal here
        proposal.executed = true;
    }*/
}
