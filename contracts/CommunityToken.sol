// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./interfaces/ICommunityFactory.sol";

contract CommunityToken is ReentrancyGuard,  ERC20Votes {

    address public immutable communityFactory;
    address public comWallet;
    address public comOwner;

    uint128 internal price; // Price in wei

    bool public mintable = true;
    bool public mintableStatusFrozen = false;

    event TokensMinted(address senderAddress, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint128 _price,
        address _communityWallet,
        address _creatorAddress
    ) ERC20(_name, _symbol) ERC20Permit(_name){
        comWallet = _communityWallet;
        comOwner = _creatorAddress;
        price = _price;
        communityFactory = msg.sender;
        _mint(_creatorAddress, 1e18);
    }

    modifier onlyCommunity{
        require(msg.sender == comWallet || msg.sender == comOwner,
            "ComToken: caller is not the community wallet or owner.");
        _;
    }

    function mint(uint128 _amount) // Amount in Tokens (not wei)
    external
    payable
    nonReentrant
    returns (bool)
    {
        require(mintable, "ComToken: minting is disabled.");
        uint256 surplus = msg.value - (price * _amount);
        require(
            surplus  >= 0,
            "Insufficient funds have been sent to purchase tokens");

        if (surplus > 0){
            (bool sent, ) = payable(msg.sender).call{value: surplus}("");
            require(sent, "ComToken: Failed to return surplus.");
        }

        (bool sent2, ) = payable(comWallet).call{value: msg.value - surplus}("");
        require(sent2, "ComToken: Failed to send funds.");

        _mint(msg.sender, _amount * 1e18); // Amount in wei

        emit TokensMinted(msg.sender, _amount);
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        address token = address(this);
        if(balanceOf(msg.sender) < ICommunityFactory(communityFactory).getParticipationThreshold(token)){
            ICommunityFactory(communityFactory).deleteMember(token, msg.sender);
        }
        return true;
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function getPrice() public view virtual returns (uint128){
        return price;
    }

    event PriceChanged(address tokenAddress, uint128 newPrice);

    function setPrice(uint128 _newPrice)
    external
    onlyCommunity
    virtual {
        price = _newPrice;
        emit PriceChanged(address(this), _newPrice);
    }

    function changeComOwner(address _newComOwner)
    external
    onlyCommunity {
        comOwner = _newComOwner;
    }

    function changeComWallet(address _newComWallet)
    external
    onlyCommunity {
        comWallet = _newComWallet;
    }

    function changeMintable(bool _mintable)
    external
    onlyCommunity
    returns (bool) {
        require(!mintableStatusFrozen, "ComToken: minting status is frozen.");
        mintable = _mintable;
        return true;
    }

    function freezeMintingStatus()
    external
    onlyCommunity
    returns (bool) {
        mintableStatusFrozen = true;
        return true;
    }
}