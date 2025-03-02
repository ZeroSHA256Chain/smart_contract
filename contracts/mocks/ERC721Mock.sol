// ERC721Mock.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC721Mock is ERC721, Ownable {
    uint256 private _tokenIdCounter;

    constructor() Ownable(msg.sender) ERC721("ERC721 Mock", "MERC721") {
        _tokenIdCounter = 0;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://myapi.com/metadata/";
    }

    function mint(address to) external onlyOwner {
        _tokenIdCounter++;
        _safeMint(to, _tokenIdCounter);
    }
}
