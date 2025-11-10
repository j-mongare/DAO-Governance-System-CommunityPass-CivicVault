//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//@title CommunityPass.sol 
//@notice this is tiered membership NFT that grants access to DAO priviledges
// @notice this contract is designed for intergration with CivicVault.sol

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";



contract CommunityPass is ERC721,ERC721Enumerable,Ownable{
    using Strings for uint256; // OpenZepplin utility library that lets you convert numbers to strings easily

    //=============State Variables===========
    uint256 public nextTokenId; // counter for minting new tokens
    address public admin; // DAO admin
    string private baseURI; // base metadata URI

    mapping (address => bool)public hasMinted; // track if user has already minted
    mapping(uint256 => Member) public members; // store member info

    //=================Struct and enum===============

    enum Tier{Bronze, Silver, Gold}

    struct Member{
        uint256 id; // token Id
        address wallet; // member's address
        Tier tier; // membership tier
        uint256 joinDate; // timestamp for when member joined
        bool active; // membership status
    }
    //===========events=====================
    event MemberJoined(address indexed user, uint256 indexed tokenId, Tier tier);
    event TierUpgraded(address indexed user, Tier newTier);
    event MembershipRevoked(address indexed user);
    event BaseURIUpdated(string newURI);
    event ContractInitialized(address indexed admin);

    //=================errors========
    error NotMember();
    error NotAdmin();
    error AlreadyMinted();
    error InvalidTier();
    error InactiveMember();
    error ZeroAddress();
    error TokenDoesNotExist();

    //============modifiers================

    modifier onlyAdmin(){
        if(msg.sender != admin) revert NotAdmin();
        _;
    }
    // modifier onlyActiveMember(){
     //   uint256 tokenId = tokenOfOwnerByIndex(msg.sender, 0);
     
     //   if(!members[id].active) revert InactiveMember();
    //    _;
    
    modifier validTier(Tier tier){

        if (uint256 (tier) > uint256 (Tier.Gold)) revert InvalidTier();
        _;
    }
    //===========Constructor===========

    constructor (string memory _baseURI, address _admin)ERC721("CommunityPass", "CPASS")Ownable(_admin){
        if (_admin == address (0)) revert ZeroAddress();
        baseURI = _baseURI;
        admin = _admin;

        emit ContractInitialized(admin);
    }
    //================Core Logic ===================
    //@notice mint membership pass
    //@dev one pass/wallet. Sets tier and marks as active

    function mintPass(address to, Tier tier) external validTier(tier){
        if(hasMinted[to]) revert AlreadyMinted();
        if (to == address(0)) revert ZeroAddress();

         uint256 id = nextTokenId++;
         _safeMint(to, id); // _safeMint() checks whether the receipient is capable of receiving ERC721 tokens. 
                            //This avoids lose of tokens permanently.

        members[id]= Member({
            id: id,
            wallet: to,
            tier: tier,
            joinDate: block.timestamp,
            active: true
        });
        hasMinted[to]=true;
       

        emit MemberJoined(to, id, tier);
    }
    //@notice upgrade a member's tier(Bronze > silver > gold)
    //@dev only callable by admin

    function upgradeTier(uint256 tokenId, Tier newTier) external 
    onlyAdmin 
    validTier(newTier){

        if(_ownerOf(tokenId)==address(0))revert TokenDoesNotExist();
        if (!members[tokenId].active) revert NotMember();

      Tier currentTier = members[tokenId].tier;
        if (uint256(currentTier) > uint256(newTier)) revert InvalidTier();

        members[tokenId].tier = newTier;
        address user = ownerOf(tokenId);

        emit TierUpgraded(user, newTier);

    }
    //@notice revoke a member's active status
    //@dev admin only

    function revokeMembership(uint256 tokenId) external onlyAdmin{
      if(_ownerOf(tokenId)==address(0))revert TokenDoesNotExist();
        members[tokenId].active = false;

         address user = ownerOf(tokenId);

        emit MembershipRevoked( user);
       

    }    //==========helpers=========
    //@notice return true if member is active 
    function _isMember(address _user) external view returns (bool){
      if(balanceOf(_user)==0)revert NotMember();
    
      uint256 tokenId = tokenOfOwnerByIndex(_user, 0);
        
         return members[tokenId].active;
    }
    function updateBaseURI(string calldata newURI)external onlyAdmin{
       baseURI = newURI;

       emit BaseURIUpdated(newURI);
    }
    function tokenURI(uint256 tokenId)public view override returns(string memory){
        if(_ownerOf(tokenId)==address(0))revert TokenDoesNotExist();
        string memory tierStr = _tierToString(members[tokenId].tier);
       return  string(abi.encodePacked(baseURI, "/", tierStr, ".json"));
    }
    function setAdmin(address newAdmin) external onlyAdmin{
        if(newAdmin == address(0)) revert NotAdmin();
        admin = newAdmin;
    }
   function getAdmin() external view returns (address){
    return admin;
   }
    function _tierToString(Tier tier)internal pure returns(string memory){
        if(tier==Tier.Bronze) return ("Bronze");
        if(tier==Tier.Silver)return ("Silver");
        if(tier == Tier.Gold)return ("Gold");
        return "";
    }
    //===================Overrides==================
    function _update(address to, uint256 tokenId, address auth)internal 
    override(ERC721, ERC721Enumerable) returns(address){
       
        return super._update(to, tokenId, auth);
    }
    function supportsInterface(bytes4 interfaceId)public view 
    override(ERC721, ERC721Enumerable) returns (bool){
       
        return super.supportsInterface(interfaceId);
    }
    function _increaseBalance(address account, uint128 amount) internal override (ERC721, ERC721Enumerable){
        super._increaseBalance(account, amount);
    }
   
   

}