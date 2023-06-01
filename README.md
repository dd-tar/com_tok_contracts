# Smart contracts for community tokenization system
This repository contains the code of the smart contracts working with ComTokBot (bot for Telegram). It is a part of final qualifying paper on the topic
"Tools for building tokenized communities".

See also ComTokBot repository:  
https://github.com/dd-tar/com_tok_bot

Transaction Signing Site:  
https://github.com/dd-tar/com_tok_tx_provider



## Main project files
`contracts/` - a folder containing smart contracts, and the interfaces they use  
`contracts/CommunityFactory.sol` -  this contract is responsible for creating communities and their tokens, stores information about members of communities. Acts as a system manager.
`contracts/Backlog.sol` - provides the ability to create tasks, their solutions, functions for launching voting for the best solutions, calculating results, rewarding for a solution.  
`contracts/Voting.sol` - implements all logic related to community voting.  
`contracts/CommunityToken.sol` - community token smart contract.  
`scripts/` - a folder containing scripts for deploying CommunityFactory and CommunityToken smart contracts  
`hardhat.config.ts` - configuration of networks and tools for working with blockchain

## Deploy smart contracts
You can use [Remix IDE](https://remix.ethereum.org/) to deploy your own instances of smart contracts (e.g. if you want to test them using Ganache or any local blockchain network)  
The sequence of actions is as follows:
1. Open [Remix IDE](https://remix.ethereum.org/)
2. In file explorer, use "Upload folder" button to upload `contracts/` directory of this repository
3. Compile each contract with `Enable optimization = 200`
4. Go to "Deploy & run transactions" section, select your account and the network to deploy to
5. Deploy `CommunityFacroty` contract, copy its address. The instance of the contract will appear  in the "Deployed contracts" section
6. Deploy `Backlog` contract with the address of CommunityFactory as an argument
7. Deploy `Voting` contract using CommunityFactory and Backlog addresses as arguments
8. Call `initializeFactory` function of your CommunityFactory instance using Backlog and Voting addresses as arguments
9. Call `initialize` function of your Backlog instance using Voting address as argument

Now you're all set!

You can use these smart contracts with ComTokBot Telegram-bot and website or write your own user interface.

_The project is a HardHat project, so you can also deploy and interact with contracts through the command line._