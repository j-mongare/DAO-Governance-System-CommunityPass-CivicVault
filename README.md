# 🏛️ DAO Governance System — CommunityPass & CivicVault

### Overview
This project demonstrates a **complete on-chain governance and staking system** built using Solidity.  
It consists of two primary smart contracts:

1. **CommunityPass.sol** — an ERC-721 NFT that represents tiered DAO membership.  
2. **CivicVault.sol** — a staking and governance vault that allows members to stake their NFTs, earn rewards, and participate in decentralized voting.

---

## 📜 Smart Contracts

### 1️⃣ CommunityPass.sol

**Purpose:**  
CommunityPass is a **tiered membership NFT** granting DAO privileges. Each wallet can mint one NFT representing their status (Bronze, Silver, or Gold).  
Admins can update tiers or revoke inactive members.

**Key Features:**
- Built on **OpenZeppelin’s ERC721Enumerable** for easy token enumeration.
- Tier system via `enum Tier { Bronze, Silver, Gold }`.
- Member tracking through a `members` mapping.
- Admin-managed upgrades and revocations.
- Base URI for metadata management.
- Access modifiers for `onlyAdmin`, `validTier`, and `onlyActiveMember`.

**Main Functions:**
| Function | Description |
|-----------|--------------|
| `mintPass(address to, Tier tier)` | Mints a membership NFT. One per wallet. |
| `upgradeTier(uint256 tokenId, Tier newTier)` | Allows admin to promote a member’s tier. |
| `revokeMembership(uint256 tokenId)` | Admin-only: deactivates a member. |
| `_isMember(address user)` | Returns true if address has an active membership. |
| `updateBaseURI(string newBaseURI)` | Updates base metadata URI for all NFTs. |

---

### 2️⃣ CivicVault.sol

**Purpose:**  
CivicVault extends DAO functionality by allowing **members to stake their CommunityPass NFTs** for governance power and reward accrual.  
It introduces **proposal creation, voting, execution, and reward claiming** — forming a simplified DAO governance model.

**Key Features:**
- Stake NFTs to gain voting power.  
- Create and vote on governance proposals.  
- Execute proposals after voting ends.  
- Optional ERC-20 reward distribution for staking.  
- Configurable quorum and voting period.  
- Admin-managed parameters and security via `ReentrancyGuard`.

**Main Components:**

| Component | Description |
|------------|-------------|
| `stake(uint256 tokenId)` | Locks NFT for voting and starts reward timer. |
| `unstake(uint256 tokenId)` | Returns NFT after proposals end and sends rewards. |
| `createProposal(string description)` | Allows members to suggest new governance actions. |
| `vote(uint256 proposalId, bool support)` | Casts a yes/no vote using staking weight. |
| `executeProposal(uint256 proposalId)` | Finalizes voting and checks quorum. |
| `claimRewards()` | Lets members claim accumulated staking rewards. |
| `configureRewards(address token, uint256 rate)` | Admin sets ERC-20 reward parameters. |

---

## 🧩 Contract Architecture

CommunityPass.sol
│
├── ERC721Enumerable
├── Ownable
│
└── CivicVault.sol
├── ReentrancyGuard
├── IERC20 (optional rewards)
└── interacts with CommunityPass (NFT staking + verification)


---

## ⚙️ Deployment Guide

1. **Deploy `CommunityPass.sol`:**
   - Provide a base URI (e.g. `"https://your-metadata-api.io/metadata/"`).
   - Set the initial admin address.

2. **Deploy `CivicVault.sol`:**
   - Pass the address of the deployed `CommunityPass` contract.
   - Optionally, pass an ERC-20 reward token (or use address(0)).
   - Define `admin`, `quorumPercentage`, and `votingPeriodSeconds`.

3. **Approve the Vault to handle NFTs:**
   - In `CommunityPass`, call:
     ```solidity
     setApprovalForAll(<CivicVault_Address>, true);
     ```

4. **Stake an NFT:**
   - `stake(tokenId)` from `CivicVault`.

5. **Create a Proposal:**
   - `createProposal("Add a new community feature")`.

6. **Vote:**
   - `vote(proposalId, true)` or `vote(proposalId, false)`.

7. **Execute Proposal:**
   - Once voting period ends, admin calls `executeProposal(proposalId)`.

---

## 🔒 Security & Best Practices

- Uses **OpenZeppelin** audited contracts (`ERC721Enumerable`, `Ownable`, `ReentrancyGuard`).
- Restrictive access control (`onlyAdmin`, `onlyMember`).
- Prevents reentrancy on sensitive operations.
- Quorum and proposal life-cycle checks to prevent manipulation.
- Designed for future integration with off-chain indexing (The Graph, Snapshot).

---

## 🧠 Learning Outcomes

By completing and experimenting with these contracts, you’ll learn:

- NFT-based **membership gating** and staking.  
- **Structs, enums, and mappings** for state organization.  
- **DAO-style proposal and voting mechanics.**  
- Secure **reward distribution** and **modifier-driven access control**.  
- Event-driven architecture for off-chain UI tracking.

---

## 📚 Tech Stack

- **Solidity:** ^0.8.23  
- **OpenZeppelin Contracts:** ERC721Enumerable, Ownable, ReentrancyGuard, IERC20  
- **Remix IDE / Hardhat** (recommended for testing and deployment)

---

## 🧾 License

This project is licensed under the **MIT License** — you’re free to use, modify, and distribute with attribution.

---



