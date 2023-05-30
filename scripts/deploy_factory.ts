import * as dotenv from 'dotenv'
import { ethers, run } from "hardhat"

import {
    CommunityFactory__factory
} from '../typechain-types'
//import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";

dotenv.config()

async function main() {
  const signers = await ethers.getSigners()
  const comFactory = await new CommunityFactory__factory(signers[0])
      .deploy()

  await comFactory.deployed();
  console.log('DAOFactory deployed at: ',  comFactory.address);

  // verify?
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error)
      process.exit(1)
    })