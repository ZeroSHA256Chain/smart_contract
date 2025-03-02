// ERC20Mock.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("Mock ERC20", "MERC20") {
        _mint(msg.sender, 1000000 * 10 ** decimals()); 
    }
}
