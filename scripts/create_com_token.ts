import * as dotenv from 'dotenv'
import { ethers} from "hardhat"

import {
    CommunityFactory
} from '../typechain-types'
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {Contract} from "ethers";

dotenv.config()

async function main() {
    let creator: SignerWithAddress;
    let comFactory: Contract;
    [creator] = await ethers.getSigners();

    const comFactoryProxyAddr = "";

    const _name = "Test";
    const _symbol = "TT";
    const _price = 5000000000000000; //ethers.utils.parseEther("0.00005");
    const _comWallet = "";
    const _creatorTgId = "";

    comFactory = await ethers.getContractAt("CommunityFactory", comFactoryProxyAddr, creator);

    const tx = await comFactory.createCommunityWithToken(_name, _symbol, _price, _comWallet, _creatorTgId);
    await tx.wait();

    console.log('CommunityToken deployed at:',  tx);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })