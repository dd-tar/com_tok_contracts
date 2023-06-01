// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CommunityFactory.sol";
import "./Voting.sol";

    enum TaskStatus {
        Created,
        Voting,
        Done,
        Closed
    }

    struct Task {
        address creator;
        // todo optional-implementer
        string name; // could be a link
        string description; // could be a link
        uint256 deadline;
        uint256 reward;
        TaskStatus status;
        mapping (uint256 => Solution) proposedSolutions; // IDs from 1 to numberOfSolutions inclusively
        uint256 numberOfProposedSolutions;
        mapping(uint256 => address) winners;
        uint256 numberOfWinners; // from 0
        // vote for the best of all solutions
    }

    struct Solution{
        address creator;
        string solution; // text OR link
    }

    struct CommunityBacklog{
        uint256 community;
        uint256 thresholdForTasks; // only for the owner of community
        mapping (uint256 => Task) tasks; // not array to avoid initialization problems, ids from 0
        uint256 numberOfTasks;
        mapping(uint256 => uint256) taskToVoting; // taskId => votingId
    }

contract Backlog is Ownable{

    mapping(uint256 => CommunityBacklog) backlogs; // backlogId == comId
    mapping(uint256 => bool) backlogExists; // communityAddr => backlogID (from backlogs[])

    CommunityFactory internal immutable communityFactory;
    Voting private votingContract;

    // tg-bot: send notification
    event BacklogCreated(uint256 communityId);
    event TaskCreated(uint256 taskId, address comToken, uint256 creator, string name, string description, uint256 deadline, uint256 reward);
    event SolutionProposed(address comToken, uint256 taskId,  uint256 solId, uint256 solver, string solutionLink);
    event VotingOnTaskStarted(uint256 comId, address comToken, uint256 taskId, uint256 votingId, string proposal, uint256 numberOfChoices, uint256 reward, uint256 deadline);
    event ResultsCounted(uint256 comId, address comToken, uint256 taskId);
    event TaskClosed(address comToken, uint256 taskId);


    constructor(
        address _communityFactory
    ){
        communityFactory = CommunityFactory(_communityFactory);
    }

    function initialize(address _votingContract) onlyOwner external {
        votingContract = Voting(_votingContract);
    }

    modifier onlyMember(uint256 _comId){
        require(communityFactory.isMember(_comId, msg.sender));
        _;
    }

    modifier onlyVerifiedMember(uint256 _comId){
        require(communityFactory.isVerifiedMember(_comId, msg.sender),
            "Sender is not verified community member.");
        _;
    }

    function createBacklog(uint256 _comId) private {
        CommunityBacklog storage cb = backlogs[_comId];
        cb.community = _comId;
        cb.thresholdForTasks = 1; // default
        backlogExists[_comId] = true;

        emit BacklogCreated(_comId);
    }

    function createTask(
        uint256 _communityId,
        string memory _name,
        string memory _description, // link to description & acceptance criteria
        uint _deadline,
        uint _reward
    ) public onlyVerifiedMember(_communityId) {
        // TODO Later: tasks for specific person
        address token = communityFactory.getMainCommunityToken(_communityId);
        uint256 userBalance = IERC20(token).balanceOf(msg.sender);
        require(userBalance >= backlogs[_communityId].thresholdForTasks, "Sender has not enough tokens to create tasks.");

        if (!backlogExists[_communityId])
            createBacklog(_communityId);

        // add task to community backlog and task counter
        uint256 taskId = backlogs[_communityId].numberOfTasks;
        Task storage newTask = backlogs[_communityId].tasks[taskId];
        newTask.creator = msg.sender;
        newTask.name = _name;
        newTask.description = _description;
        newTask.deadline = block.timestamp + _deadline * 1 hours;
        newTask.reward = _reward;
        newTask.status = TaskStatus.Created;
        uint256 creator_id = communityFactory.getMemberTgId(_communityId, msg.sender);

        //backlogs[_communityId].tasks[taskId] = newTask;
        backlogs[_communityId].numberOfTasks++;

        emit TaskCreated(taskId, token, creator_id, _name, _description, newTask.deadline, _reward);
    }

    function changeThresholdForTasks(uint256 _comId, uint256 _threshold) public{
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        require(communityFactory.isComOwner(_comId, msg.sender), "For community owner only.");

        backlogs[_comId].thresholdForTasks = _threshold;
    }

    function proposeSolution(
        uint256 _comId,
        uint256 _taskId,
        string memory _solution
    ) public onlyVerifiedMember(_comId){
        require(_taskId < backlogs[_comId].numberOfTasks, "Task doesn't exist.");
        // check for overload of the string memory _solution
        require(block.timestamp < backlogs[_comId].tasks[_taskId].deadline, "The deadline of the task has passed.");
        require(backlogs[_comId].tasks[_taskId].status == TaskStatus.Created);

        backlogs[_comId].tasks[_taskId].numberOfProposedSolutions++;
        uint256 solId = backlogs[_comId].tasks[_taskId].numberOfProposedSolutions;
        Solution storage sol = backlogs[_comId].tasks[_taskId].proposedSolutions[solId];
        sol.creator = msg.sender;
        sol.solution = _solution; // TODO Later: check that it is IPFS

        uint256 member_id = communityFactory.getMemberTgId(_comId, msg.sender);
        address token = communityFactory.getMainCommunityToken(_comId);

        emit SolutionProposed(token, _taskId, solId, member_id, _solution);
    }

    // anyone who has threshold of community token can start voting after the deadline on the task
    function startVoting(uint _taskId, uint _comId, uint256 _votingDeadline) public onlyVerifiedMember(_comId) {
        require(_taskId < backlogs[_comId].numberOfTasks, "Task doesn't exist.");
        require(block.timestamp > backlogs[_comId].tasks[_taskId].deadline, "The deadline of the task hasn't pass.");
        require(backlogs[_comId].tasks[_taskId].status == TaskStatus.Created, "The task is already on voting or closed.");

        string memory description = backlogs[_comId].tasks[_taskId].description;
        uint256 numberOfChoices = backlogs[_comId].tasks[_taskId].numberOfProposedSolutions;
        uint256 reward = backlogs[_comId].tasks[_taskId].reward;
        uint256 votingId = votingContract.createProposal(_comId, description, numberOfChoices, _votingDeadline, msg.sender);
        uint256 deadline = block.timestamp + _votingDeadline * 1 hours;

        backlogs[_comId].taskToVoting[_taskId] = votingId;

        backlogs[_comId].tasks[_taskId].status = TaskStatus.Voting;

        address token = communityFactory.getMainCommunityToken(_comId);

        emit VotingOnTaskStarted(_comId, token, _taskId, votingId, description, numberOfChoices, reward, deadline);
    }

    function countResults(uint256 _comId, uint256 _taskId) public onlyVerifiedMember(_comId){
        require(_taskId < backlogs[_comId].numberOfTasks,"Task doesn't exist");
        uint256 proposalId = backlogs[_comId].taskToVoting[_taskId];
        require(backlogs[_comId].tasks[_taskId].status == TaskStatus.Voting, "Task is not on voting");
        require(proposalId != 0, "This task has no voting.");

        uint256[] memory approvedSolutions = votingContract.executeVoting(_comId, proposalId);

        backlogs[_comId].tasks[_taskId].numberOfWinners = approvedSolutions.length;
        address solver;
        for(uint i = 0; i < approvedSolutions.length; i++){
            solver = backlogs[_comId].tasks[_taskId].proposedSolutions[approvedSolutions[i]].creator;
            backlogs[_comId].tasks[_taskId].winners[i] = solver;
        }
        backlogs[_comId].tasks[_taskId].status = TaskStatus.Done;

        address token = communityFactory.getMainCommunityToken(_comId);

        emit ResultsCounted(_comId, token, _taskId);
    }

    function rewardSolversAndClose(uint256 _comId, uint256 _taskId) public payable onlyVerifiedMember(_comId){
        require(_taskId < backlogs[_comId].numberOfTasks, "Task doesn't exist");
        require(backlogs[_comId].tasks[_taskId].status == TaskStatus.Done, "Results wasn't counted");
        require(msg.value >= backlogs[_comId].tasks[_taskId].numberOfWinners * backlogs[_comId].tasks[_taskId].reward,
            "Not enough funds to reward");
        // send funds from msg.sender to solvers-winners
        backlogs[_comId].tasks[_taskId].status = TaskStatus.Closed;
        if(backlogs[_comId].tasks[_taskId].reward != 0){
            uint256 numberOfWinners = backlogs[_comId].tasks[_taskId].numberOfWinners;
            for(uint i = 0; i < numberOfWinners; i++){
                bool sent = payable(backlogs[_comId].tasks[_taskId].winners[i])
                .send(backlogs[_comId].tasks[_taskId].reward);
                require(sent, "Backlog: Failed to send reward");
            }
        }
        address token = communityFactory.getMainCommunityToken(_comId);
        emit TaskClosed(token, _taskId);
    }

    // _________________________________________________________________________________________________________________

    function getTaskName(uint256 _comId, uint256 _taskId) public view returns (string memory){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        if(_taskId >= backlogs[_comId].numberOfTasks)
            return " ";
        else
            return backlogs[_comId].tasks[_taskId].name;
    }

    function getTaskDescription(uint256 _comId, uint256 _taskId) public view returns (string memory){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        if(_taskId >= backlogs[_comId].numberOfTasks)
            return " ";
        else
            return backlogs[_comId].tasks[_taskId].description;
    }

    function getTaskCreator(uint256 _comId, uint256 _taskId) public view returns (uint256){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        if(_taskId >= backlogs[_comId].numberOfTasks)
            return 0;

        address crAddr = backlogs[_comId].tasks[_taskId].creator;
        uint256 crId = communityFactory.getMemberTgId(_comId, crAddr);
        return crId;
    }

    function getTaskDeadline(uint256 _comId, uint256 _taskId) public view returns (uint256){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        if(_taskId >= backlogs[_comId].numberOfTasks)
            return 0;

        uint256 deadline = backlogs[_comId].tasks[_taskId].deadline;
        return deadline;
    }

    function getTaskReward(uint256 _comId, uint256 _taskId) public view returns (uint256){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        if(_taskId >= backlogs[_comId].numberOfTasks)
            return 0;

        uint256 reward = backlogs[_comId].tasks[_taskId].reward;
        return reward;
    }

    function getTaskStatus(uint256 _comId, uint256 _taskId) public view returns (string memory){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        if(_taskId >= backlogs[_comId].numberOfTasks)
            return "";

        TaskStatus status = backlogs[_comId].tasks[_taskId].status;
        if(status == TaskStatus.Created) return "Created";
        if(status == TaskStatus.Voting) return "Voting";
        if(status == TaskStatus.Done) return "Done";
        if(status == TaskStatus.Closed) return "Closed";
        return "";
    }

    function getSolutionById(uint256 _comId, uint256 _taskId, uint256 _solId) public view returns (string memory){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        require(_taskId < backlogs[_comId].numberOfTasks, "Task doesn't exist");
        require(_solId <= backlogs[_comId].tasks[_taskId].numberOfProposedSolutions, "There's no such solution.");

        return backlogs[_comId].tasks[_taskId].proposedSolutions[_solId].solution;
    }

    function getNumberOfSolutions(uint256 _comId, uint256 _taskId) public view returns (uint256){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        require(_taskId < backlogs[_comId].numberOfTasks, "Task doesn't exist");

        return backlogs[_comId].tasks[_taskId].numberOfProposedSolutions;
    }

    function getNumberOfTasks(uint256 _comId) public view returns (uint256){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");

        return backlogs[_comId].numberOfTasks;
    }

    function getVotingByTaskId(uint256 _comId, uint256 _taskId) public view returns(uint256){
        require(communityFactory.communityAt(_comId) != address(0), "Community doesn't exist.");
        require(_taskId < backlogs[_comId].numberOfTasks, "Task doesn't exist");
        require(backlogs[_comId].tasks[_taskId].status == TaskStatus.Voting ||
        backlogs[_comId].tasks[_taskId].status == TaskStatus.Closed ||
            backlogs[_comId].tasks[_taskId].status == TaskStatus.Done, "Task has no voting");

        return backlogs[_comId].taskToVoting[_taskId];
    }
}
