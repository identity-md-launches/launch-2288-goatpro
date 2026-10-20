// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev Random sequences over a closed set of holders, including self-transfers.
contract GoatProHandler is Test {
    GoatPro public immutable token;
    address[4] public actors;

    constructor(GoatPro token_, address initialHolder) {
        token = token_;
        actors[0] = initialHolder;
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
    }

    function transfer(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowanceBefore = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, balance < allowanceBefore ? balance : allowanceBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        assertEq(
            token.allowance(owner, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }
}

contract GoatProInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    GoatPro internal token;
    GoatProHandler internal handler;

    function setUp() public {
        address initialHolder = makeAddr("invariant deployer");
        vm.prank(initialHolder);
        token = new GoatPro();
        handler = new GoatProHandler(token, initialHolder);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = GoatProHandler.transfer.selector;
        selectors[1] = GoatProHandler.approve.selector;
        selectors[2] = GoatProHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndSumOfBalancesStayConstant() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
