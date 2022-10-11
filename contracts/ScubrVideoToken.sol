// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import './ScubrEngagementToken.sol';


contract ScubrVideoToken is ERC721, Pausable, Ownable, ERC721URIStorage, ERC721Burnable, ERC2981, ERC721Enumerable {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    // store erc20 token address
    ScubrEngagementToken private erc20TokenAddress;

    // data for marketplace listing
    struct Listing {
        uint256 price;
        bool active;
    }

    // mapping for tokenId => listing
    mapping(uint256 => Listing) private _listings;

    // array of all listings
    uint256[] private _allListings;

    // Sales details of a token
    struct Sale {
        address buyer;
        uint256 price;
        uint256 timestamp;
    }

    // mapping for tokenId => array of sales
    mapping(uint256 => Sale[]) private _sales;

    // mapping for tokenId => creator address
    mapping(uint256 => address) public _creators;


    constructor(ScubrEngagementToken _erc20TokenAddress) ERC721("Scubr Video Token", "SVT") {
        // default royalty fee set to 8%
        _setDefaultRoyalty(msg.sender, 800);

        erc20TokenAddress = _erc20TokenAddress;
    }


    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // function to mint NFTs with default royalty (i.e: 8%)
    function mintNFT(address to, string memory uri) public returns (uint256) {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        _creators[tokenId] = to;

        return tokenId;
    }

    // function to mint NFTs with custom royalty
    function mintNFTWithRoyalty(address to, string memory uri, uint96 royaltyAmount) public returns (uint256) {
        uint256 tokenId = mintNFT(to, uri);
        _setTokenRoyalty(tokenId, to, royaltyAmount);

        return tokenId;
    }


    // function to get token URI
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }


    // internal function to burn NFTs along with royalty info
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }



    // public function to burn NFTs along with royalty info
    function burnNFT(uint256 tokenId)
        public {
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner of the token");

        // only can be burned if no sales and not listed
        require(_sales[tokenId].length == 0, "Token has been sold");
        require(!_listings[tokenId].active, "Token is listed");

        _burn(tokenId);
    }

   // check if a tokenId is minted or not
    function isMinted(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    // check if a tokenId is burned or not
    function isBurned(uint256 tokenId) public view returns (bool) {
        return !_exists(tokenId);
    }


    // function to list a token for sale
    function listToken(uint256 tokenId, uint256 price) public {
        _requireMinted(tokenId);
        require(ownerOf(tokenId) == msg.sender, "You are not the owner of this token");
        require(price > 0, "Price should be greater than 0");
        require(!_listings[tokenId].active, "Token is already listed");


        _listings[tokenId] = Listing(price, true);
        _allListings.push(tokenId);
    }

    // function to unlist a token
    function unlistToken(uint256 tokenId) public {
        _requireMinted(tokenId);
        require(ownerOf(tokenId) == msg.sender, "You are not the owner of this token");
        require(_listings[tokenId].active, "Token is not listed");


        _listings[tokenId].active = false;
        removeListing(tokenId);
    }

    // function to remove listing
    function removeListing(uint256 tokenId) internal {
        uint256 index = 0;
        for (uint256 i = 0; i < _allListings.length; i++) {
            if (_allListings[i] == tokenId) {
                index = i;
                break;
            }
        }

        for (uint256 i = index; i < _allListings.length - 1; i++) {
            _allListings[i] = _allListings[i + 1];
        }
        _allListings.pop();
    }

    // function to get listing details of a token
    function getListingDetails(uint256 tokenId) public view returns (uint256, bool) {
        _requireMinted(tokenId);
        return (_listings[tokenId].price, _listings[tokenId].active);
    }

    // function to buy a token
    function buyToken(uint256 tokenId) public payable {
        _requireMinted(tokenId);

        require(_listings[tokenId].active, "Token is not listed");

        // store listing price
        uint256 price = _listings[tokenId].price;


        require(msg.value >= price, "Insufficient amount sent");


        address payable seller = payable(ownerOf(tokenId));

        // burn 2% of the price from msg.value
        uint256 burnAmount = (price * 2) / 100;
        uint256 remainingAmount = price - burnAmount;

        // transfer 2% to burn address
        payable(0x000000000000000000000000000000000000dEaD).transfer(burnAmount);

       // get royalty info of the token
         (address royaltyReceiver, uint256 royaltyAmount) = royaltyInfo(tokenId, remainingAmount);

        // transfer remaining amount to seller
        seller.transfer(remainingAmount - royaltyAmount);

        // transfer royalty amount to royalty receiver
        payable(royaltyReceiver).transfer(royaltyAmount);

        // transfer token to buyer
        _transfer(seller, msg.sender, tokenId);

        // update listing status
        _listings[tokenId].active = false;

        // remove listing from all listings array
        removeListing(tokenId);

        // add sale details to sales array
        _sales[tokenId].push(Sale(msg.sender, price, block.timestamp));


    }


    // function to get all the tokenIds of the user
    function getAllTokensOfOwner(address owner) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokens = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }
        return tokens;
    }


    // function to get all listed tokens Info
    function getAllListedTokens() public view returns (uint256[] memory) {
        // To reduce gas fees, loop through the _allListings in the frontend
        // and use getTokenInfo function to get the details of each token
        return _allListings;
    }

    // function to get all sales of a token
    function getAllSalesOfToken(uint256 tokenId) public view returns (Sale[] memory) {
        _requireMinted(tokenId);
        return _sales[tokenId];
    }

    // function to get all info of a token i.e: royalty, sales, listing details, tokenURI etc
    function getTokenInfo(uint256 tokenId) public view returns (string memory, uint256, bool, uint256, address, Sale[] memory) {
        _requireMinted(tokenId);
        (address royaltyReceiver, uint256 royaltyAmount) = royaltyInfo(tokenId, 100);
        return (tokenURI(tokenId), _listings[tokenId].price, _listings[tokenId].active, royaltyAmount, royaltyReceiver, _sales[tokenId]);
    }

    // function to get all created tokens alone of a user (not including bought tokens)
    function getCreatedTokensOfUser() public view returns (uint256[] memory) {
        uint256[] memory allTokens = getAllTokensOfOwner(msg.sender);

        // use _creators mapping to get the tokens created by the owner
        uint256[] memory createdTokens = new uint256[](allTokens.length);
        uint256 index = 0;
        for (uint256 i = 0; i < allTokens.length; i++) {
            if (_creators[allTokens[i]] == msg.sender) {
                createdTokens[index] = allTokens[i];
                index++;
            }
        }

        return createdTokens;
    }

    // function to get all bought tokens of a user (not including created tokens)
    function getBoughtTokensOfUser() public view returns (uint256[] memory) {
        uint256[] memory allTokens = getAllTokensOfOwner(msg.sender);

        // use _creators mapping to get the tokens created by the owner
        uint256[] memory boughtTokens = new uint256[](allTokens.length);
        uint256 index = 0;
        for (uint256 i = 0; i < allTokens.length; i++) {
            if (_creators[allTokens[i]] != msg.sender) {
                boughtTokens[index] = allTokens[i];
                index++;
            }
        }

        return boughtTokens;
    }


}