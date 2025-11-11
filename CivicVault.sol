//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//@title CivicVault.sol
//@notice staking + governance vault that accepts communityPass NFTs to acquire voting power


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CommunityPass.sol"; 

contract CivicVault is ReentrancyGuard{
    ///=================State ==============
    CommunityPass public membershipToken; // community pass contract reference
    IERC20 public rewardToken; // address(0) disables rewards 
    address public admin;
    uint256 public totalStaked;
    uint256 public activeProposals;

    // single staked token per user (simple model). If you want multiple tokens, use mapping -> array or nested mapping
    mapping (address => uint256 )public stakedTokenOf;  // staker => tokenId

    // stake timestamps for rewards 
    mapping(address => uint256 ) public stakeTimestamp;

    // governance proposals 
    uint256 public nextProposalId;
    mapping( uint256 => Proposal) public proposals;

    // quorum and thresholds
    uint8 public quorumPercentage; // eg 20%
    uint256 public votingPeriodSeconds;
    uint256 public rewardRatePerSecond; // used if address(rewardToken)!= address(0)

    //=============Structs and Enums===================

    enum VoteChoice{None, Yes, No}

    struct Proposal{
        uint256 id;
        address proposer;
        string description;
        uint256 voteStart;
        uint256 voteEnd;
        uint256 yesWeight;
        uint256 noWeight;
        bool executed;

        // mapping(address => VoteChoice) votes;  // cannot be returned; use helper view function
        // store vote tracking as mapping in a nested mapping: mapping(uint256 => mapping(address => VoteChoice)) votes;
    }
    // votes per proposal (separate mapping so that proposal can be returned from stoprage)

    mapping(uint256 => mapping(address => VoteChoice))public votes;

    //=================Events=======================
    
    event Staked(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    event Unstaked(address indexed user, uint256 indexed tokenId, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 amount);
    event ProposalCreated(uint256 indexed id, address indexed proposer, string description, uint256 voteStart, uint256 voteEnd);
    event Voted(address indexed user, uint256 indexed proposalId, VoteChoice choice, uint256 weight);
    event ProposalExecuted(uint256 indexed id, bool passed);
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event RewardConfigUpdated(address indexed rewardToken, uint256 rewardRatePerSecond);
    event GovernanceParamsUpdated(uint256 quorumPercentage, uint256 votingPeriodSeconds);
    event ContractInitialized(address indexed admin);

    //====================eRRORS============================
    error NotAdmin();
    error NotMember();
    error FuckOff();
    error AlreadyStaked();
    error NotOwnerOfToken();
    error ProposalDoesNotExist();
    error VotingNotActive();
    error AlreadyVoted();
    error VotingNotEnded();
    error ProposalAlreadyExecuted();
    error QuorumNotReached();
    error TransferFailed();
    error ZeroAddress();
    error NotApproved();
    error TokenDoesNotExist();
    error UnstakingNotAllowed();
    error DescriptionEmpty();
    error InvalidQuorumPercentage();
    error InvalidVotingPeriod();

    //=============Modifiers=======================

    modifier onlyAdmin(){
        if(msg.sender != admin)revert NotAdmin();
        _;
    }
    modifier onlyMember(){
        //@notice a user is a memebr if they have staked or are holders of CPASS(memebrshipToken)
        bool staked = stakedTokenOf[msg.sender] != 0;
        bool holder = membershipToken.isMember(msg.sender);
        if(!staked && !holder)revert NotMember();
        _;
        
    }
    modifier proposalExists(uint256 proposalId){
        if(proposalId == 0 || proposalId > nextProposalId)revert ProposalDoesNotExist();
        _;
    }
    modifier proposalActive(uint256 proposalId){
        Proposal storage p = proposals[proposalId];
        if(block.timestamp < p.voteStart || block.timestamp > p.voteEnd)revert VotingNotActive();
        _;
    }
    modifier proposalEnded(uint256 proposalId){
      Proposal storage p = proposals [proposalId];
        if(block.timestamp <= p.voteEnd) revert VotingNotEnded();
        _;
    }
       //========================Constructor========================
        /**
     * @dev Set initial references and governance params.
     * @param _membershipToken Address of CommunityPass
     * @param _rewardToken Optional ERC20 rewards token (address(0) to disable)
     * @param _admin Initial admin address
     * @param _quorumPercent Initial quorum percentage (0-100)
     * @param _votingPeriodSeconds Default voting duration in seconds
     */

       constructor (
       address _membershipToken, 
       address _rewardToken, 
       address _admin, 
       uint256 _quorumPercentage, 
       uint256 _votingPeriodSeconds,
       uint256 _rewardRatePerSecond){

        if ( _admin == address(0)|| _membershipToken == address(0)) revert ZeroAddress();
        if (_quorumPercentage > 100)revert InvalidQuorumPercentage();
        if (_votingPeriodSeconds==0)revert InvalidVotingPeriod();

        membershipToken = CommunityPass(_membershipToken);
        rewardToken = IERC20(_rewardToken);
        admin = _admin;
        quorumPercentage = _quorumPercentage;
        votingPeriodSeconds =  _votingPeriodSeconds;
        rewardRatePerSecond= _rewardRatePerSecond;

        nextProposalId= 1;

        emit ContractInitialized(admin);
       }

       //===============Staking Functions============================
       /**
     * @notice Stake a CommunityPass NFT to gain voting power and start reward timer.
     * @dev Checks:
     *  - caller must own tokenId in CommunityPass (membershipToken.ownerOf)
     *  - caller must not already have a staked token (or support multiple)
     *  - membershipToken must be approved for transfer by caller or owner
     *  - transfer token into this contract (membershipToken.transferFrom)
     *  - set stakedTokenOf[msg.sender], stakeTimestamp, increment totalStaked
     *  - emit Staked
     */

     function stake(uint256 tokenId)external nonReentrant {
        if (stakedTokenOf[msg.sender] != 0) revert AlreadyStaked();
        if(tokenId==0) revert TokenDoesNotExist();

        address owner = membershipToken.ownerOf(tokenId);
        if (owner != msg.sender) revert NotOwnerOfToken();

        // @notice ensure approval

      address approved=  membershipToken. getApproved(tokenId);
      bool operator = membershipToken.isApprovedForAll(msg.sender, address(this));
      if(approved != address(this)&& !operator )revert NotApproved();

     stakedTokenOf[msg.sender] = tokenId;
      stakeTimestamp[msg.sender]= block.timestamp;
      totalStaked+=1;

      membershipToken.transferFrom(msg.sender, address(this), tokenId); // reverts on failure

    

      emit Staked(msg.sender, tokenId, block.timestamp);
     }
     /**
     * @notice Unstake a previously staked token and optionally claim accrued rewards.
     * @dev Checks:
     *  - caller must have staked that token (stakedTokenOf[msg.sender] == tokenId)
     *  - ensure user is not participating in active proposals where stake is required
     *  - calculate reward based on stakeTimestamp and rewardRatePerSecond
     *  - transfer rewardToken (if configured)
     *  - transfer NFT back to caller
     *  - clear stake state and decrement totalStaked
     *  - emit Unstaked and RewardClaimed (if any)
     */

     function unstake(uint256 tokenId)external nonReentrant proposalEnded(proposalId) {
        if (stakedTokenOf[msg.sender] != tokenId)revert FuckOff();

        if(activeProposals > 0){

         // check only active proposals indexes; to keep gas low we track activeProposals count,
            // but we also need to know which proposals are active. To avoid full scan, we disallow unstake
            // when (activeProposals > 0) ...... if you have voted in any currently open proposal.
            // We scan proposals in a limited window: that is, from (nextProposalId - activeProposals) to nextProposalId-1

            uint256 end = nextProposalId;

            //@notice  tenary operation for simple if/else => condition? valueIfTrue: valueIfFalse;

            uint256 start = end > activeProposals? end - activeProposals: 1;

            for(uint256 pid = start; pid < end; ++pid){
               Proposal storage p = proposals[pid];
               if (block.timestamp >= p.voteStart && block.timestamp < p.voteEnd){
                  if (votes[pid][msg.sender] != VoteChoice.None) revert UnstakingNotAllowed();
               } 

            }
        }
    
      // calculate reward amount

         uint256 rewardAmount = 0;

      //@notice address(0) disables rewards

        if (address(rewardToken) != address(0) && rewardRatePerSecond > 0){
         uint256 start = stakeTimestamp[msg.sender];
         if(start != 0){
            uint256 stakedFor = block.timestamp - start;

            uint256 rewardAmount = rewardRatePerSecond * stakedFor;

            bool sent = rewardToken.transfer(msg.sender, rewardAmount);
            if(!sent) revert TransferFailed();

            emit RewardClaimed(msg.sender, rewardAmount);
         }

        }

         // transfer NFT  to msg.sender

         stakedTokenOf[msg.sender]= 0 ;
         stakeTimestamp[msg.sender]= 0 ;
         totalStaked -= 1;

         membershipToken.transferFrom(address(this), msg.sender, tokenId);

         emit Unstaked(msg.sender, tokenId, block.timestamp);
      
} 
       /**
     * @notice Claim rewards without unstaking.
     * @dev Checks:
     *  - caller must have an active stake
     *  - compute rewards since last claim (if you implement per-user lastClaimed timestamps)
     *  - transfer rewardToken to caller
     */
     function claimRewards()external nonReentrant{
        if(stakedTokenOf[msg.sender]== 0)revert NoStake();
        if (address(rewardToken)== address(0) || rewardRatePerSecond == 0)revert TransferFailed();

        uint256 start = stakeTimestamp[msg.sender];
        if(start == 0) revert TransferFailed();

        uint256 stakedFor = block.timestamp - start;
           uint256 rewardAmount = stakedFor * rewardRatePerSecond;

           // reset stakeTimestamp to now!
           stakeTimestamp[msg.sender] = block.timestamp;

           bool sent = rewardToken.transfer(msg.sender, rewardAmount);
           if(!sent)revert Transferfailed();

            emit RewardClaimed(msg.sender, rewardAmount);
         } 

        /////===========================Governance Logic=========================

        /**
     * @notice Create a proposal. Only members (staked OR holders depending on design).
     * @param description Human-readable description of the proposal.
     * @param votingPeriodSeconds Custom period (optional) otherwise default votingPeriodSeconds used.
     * @dev Checks:
     *  - caller must be a member (onlyMember)
     *  - description not empty
     *  - create Proposal struct: id, proposer, description, voteStart, voteEnd, yesWeight=0, noWeight=0, executed=false
     *  - emit ProposalCreated
     */

     function createProposal(uint256 proposalId, string calldata description) external onlyMember returns (uint256){

        if(bytes(description).length==0)revert DescriptionEmpty();
        uint256 period = votingPeriodSeconds== 0 ? 4 days: votingPeriodSeconds; // sets default voting period to 4 days

        uint256 pid = nextProposalId++ ;

        Proposal storage pid = proposals[pid];

        p.id = pid;
        p.proposer= msg.sender;
        p.description = description;
        p.voteStart= block.timestamp;
        p.voteEnd= block.timestamp + period;
        p.yesWeight=0;
        p.noWeight=0;
        p.executed= false;

        activeProposals += 1;

        return pid;

        emit ProposalCreated(pid, msg.sender, p.description,p.voteStart, p.voteEnd );
     } 
     /**
     * @notice Vote on an active proposal. Each staked token = 1 vote by default (or use voting weights).
     * @param proposalId proposal identifier
     * @param support true => yes, false => no
     * @dev Checks:
     *  - proposal exists and is active (proposalActive)
     *  - caller must be member (onlyMember)
     *  - caller must not have already voted on this proposal (votes[proposalId][msg.sender] == None)
     *  - determine voting weight (default 1 per staked token; if multiple tokens allowed, calculate accordingly; or use votingWeight mapping)
     *  - record vote in votes[proposalId][msg.sender] and increment yesWeight/noWeight
     *  - emit Voted
     */
     function vote(uint256 proposalId, bool support)external onlyMember proposalExists(proposalId)proposalActive(proposalId){
        if(votes[proposalId][msg.sender] != VoteChoice.None) revert AlreadyVoted();

        uint256 weight = _votingWeight(msg.sender);
        if (weight==0) weight = 1;

       
        if(support) {
            votes[proposalId][msg.sender]= VoteChoice.Yes;
            proposals[proposalId].yesWeight += weight;

             emit Voted(msg.sender, proposalId, VoteChoice.Yes, weight);

        }else {
            votes[proposalId][msg.sender]= VoteChoice.No;
            proposals[proposalId].noWeight += weight;

             emit Voted(msg.sender, proposalId, VoteChoice.No, weight);
        }
       

     }
     

     
     /**
     * @notice Execute a proposal after voting ends. Admin (or DAO) can call to finalize the proposal.
     * @dev Checks:
     *  - proposal exists and voting ended (proposalEnded)
     *  - proposal not already executed
     *  - compute total participation and check quorum:
     *      (yesWeight + noWeight) * 100 >= totalStaked * quorumPercentage
     *  - determine passed = yesWeight > noWeight
     *  - mark executed = true
     *  emit ProposalExecuted
     */
     function ExecuteProposal(uint256 proposalId)external onlyAdmin proposalEnded(proposalId){
         Proposal storage p = proposals[proposalId];
        if (p.executed)revert ProposalAlreadyExecuted();

        uint256 totalVotes = p.yesWeight + p.noWeight;

        // check quorum......quorum reached == (totalVotes * 100) >= (totalStaked * quorumPercentage)

        if(totalVotes * 100 < totalStaked * quorumPercentage)revert QuorumNotReached();
        if (totalStaked== 0) revert QuorumNotReached();

        bool passed = p.yesWeight > p.noWeight;
        if(passed) p.executed = true;

         // mark proposal not active 

         if(activeProposals > 0) activeProposals -= 1 ;

            
        
        emit ProposalExecuted(proposalId, passed);
     }
     
    /**
     * @notice Read-only helper: get top-level proposal fields.
     * @dev Returns id, proposer, description, voteStart, voteEnd, yesWeight, noWeight, executed.
     */
     function getProposal(uint256 proposalId)external view proposalExists(proposalId) returns(
     uint256 id,
     address proposer, 
     string memory description,
     uint256 voteStart, 
     uint256 voteEnd, 
     uint256 yesWeight,
     uint256 noWeight, 
     bool executed){

        Proposal storage p = proposals[proposalId];

        return(
        p.id,
        p.proposer,
        p.description,
        p.voteStart,
        p.voteEnd,
        p.yesWeight,
        p.noWeight,
        p.executed);

      }

      //==================Admin Functions=====================================

      /**
     * @notice Update quorum percentage (onlyAdmin).
     * @dev quorumPercentage must be BETWEEN 0-100
     */

     function setQuorumPercentage (uint8 _quorumPercentage) external onlyAdmin{
        if (_quorumPercentage > 100) revert InvalidQuorumPercentage();
        quorumPercentage = _quorumPercentage;

          emit GovernanceParamsUpdated(quorumPercentage, votingPeriodSeconds);

        
     }
     
    /**
     * @notice Configure reward token and rate.
     */ 
     function configureRewards(address _rewardToken, uint256 _rewardRatePerSecond) external onlyAdmin{
        if (_rewardToken == address(0)) revert ZeroAddress();
        rewardToken = IERC20(_rewardToken);
        rewardRatePerSecond = _rewardRatePerSecond;

        emit RewardConfigUpdated(rewardToken,  rewardRatePerSecond);
     }

      /**
     * @notice Set default voting period seconds.
     */

     function setVotingPeriod(uint256 _votingPeriodSeconds)external onlyAdmin{
        if (_votingPeriodSeconds == 0) revert InvalidVotingPeriod();
        votingPeriodSeconds = _votingPeriodSeconds;

        emit GovernanceParamsUpdated(quorumPercentage, votingPeriodSeconds);

     }

     function setAdmin(address newAdmin) external onlyAdmin{
        if (newAdmin == address(0)) revert ZeroAddress();
        address oldAdmin = admin;
        admin= newAdmin;

        emit AdminUpdated (oldAdmin, newAdmin);
     }
     //=================Internal Helpers================

     /**
     * @notice Compute voting weight for a given account.
     * @dev Default: 1 if acc has staked token and 0 if account has no staked token; 
   
     */

     function _votingWeight(address account) internal view returns (uint256 weight){
        if (account == address(0))revert ZeroAddress();

       // uint256 weight = stakedTokenOf[account] > 0 ? 1 : 0 ;

        if(stakedTokenOf[account] != 0) return 1;
        return 0;
          
      
     }
     /**
     * @notice Compute reward amount for an account based on stakeTimestamp and rewardRatePerSecond.
     */

     function _computeReward(address account) internal view returns(uint256){
        if (account == address(0))revert ZeroAddress();

            uint256 rewardAmount = 0 ;
            if (rewardAmount == 0 && RewardRatePerSecond == 0) return 0; 
            
            uint256 start = stakeTimestamp[account];

            // compute the duration user/acc has staked 

            if (start != 0) uint256 stakedFor = block.timestamp - start;

            
            return (rewardAmount = stakedFor * rewardRatePerSecond);
                      

  }
 function _proposalExists (uint256 proposalId) internal view returns (bool){
       return (proposalId != 0 && proposalId < nextProposalId);

     
   
    }

}


