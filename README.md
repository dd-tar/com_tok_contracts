## Available Scripts

In the project directory, you can run:

### `npx hardhat compile`

Compiles the project.


### `npx hardhat run ./script/deploy_factory.ts --network <your_network>`

Deploys the DAOFactory contract to the selected network.

### `npx hardhat run ./script/create_token.ts --network <your_network>`

Deploys the DAOToken contract to the selected network.

### `npx hardhat getPrice --network <your_network>`

Makes a contract call to return the value of the token exchange rate.  
The address of the token should be specified in "getPrice" task in hardhat.config.ts file.

### `npx hardhat mintTokens --network <your_network>`

Makes a contract interaction to mint some tokens.  
The amount and address of the token should be specified in "mintTokens" task in hardhat.config.ts file.  

**Note: Don't forget to create your own .env file modeled after .example.env with private keys of the developer's address.**  
  
You can perform any interactions with a deployed contract using tasks like getPrice or mintTokens.
