# 🏦 Bitcoin-Backed Community Savings Pool

A decentralized savings pool smart contract that enables community members to create fixed-term savings vaults with automated rotation-based withdrawals.

## 🎯 Features

- ✨ Pool initialization and member management
- 💰 Fixed minimum deposit amount
- 🔒 Time-locked savings periods
- 🔄 Fair rotation-based withdrawal system
- 👥 Member status tracking

## 📝 Contract Functions

### Administrative Functions
- `initialize-pool`: Start the savings pool
- `join-pool`: Become a pool member

### Member Functions
- `deposit`: Add funds to the pool (minimum 1M uSTX)
- `request-withdrawal`: Signal intent to withdraw
- `process-withdrawal`: Execute withdrawal during your rotation

### Read-Only Functions
- `get-pool-info`: View pool statistics
- `get-member-info`: Check member details

## 🚀 Getting Started

1. Deploy the contract to the Stacks blockchain
2. Initialize the pool using `initialize-pool`
3. Members join using `join-pool`
4. Make deposits with `deposit`
5. Request withdrawals after lock period
6. Process withdrawals during rotation

## ⚙️ Technical Details

- Lock Period: 144 blocks (~24 hours)
- Minimum Deposit: 1,000,000 uSTX
- Withdrawal Distribution: Equal split among members

## 🔐 Security

- Time-locked withdrawals
- Member authentication
- Protected contract functions
- Automated rotation system
```

Git commit message:
```
feat: Implement Bitcoin-Backed Community Savings Pool MVP with rotation-based withdrawals
```

PR Title:
```
MVP: Bitcoin-Backed Community Savings Pool Smart Contract
```

PR Description:
```
This PR introduces the MVP implementation of the Bitcoin-Backed Community Savings Pool smart contract with the following features:

- Pool initialization and member management system
- Secure deposit mechanism with minimum amount requirement
- Time-locked savings with 144-block period
- Fair rotation-based withdrawal system
- Member status tracking and verification
- Comprehensive pool information queries

The implementation focuses on core functionality while maintaining security and usability. All core features have been implemented and tested for the initial release.

Testing Instructions:
1. Deploy contract
2. Initialize pool
3. Add members
4. Test deposits
5. Verify lock period
6. Test withdrawal rotation
