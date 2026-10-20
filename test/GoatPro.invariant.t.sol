// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev Only these four actors receive tokens. Ghost state is derived from authorized
/// calls, never copied from the token's observed balances or allowances.
contract GoatProHandler is Test {
    GoatPro public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(GoatPro token_, address initialHolder) {
        token = token_;
        actors[0] = initialHolder;
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        expectedBalance[initialHolder] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        _transfer(from, to, amount);
    }

    function transferEntireBalance(uint256 fromIndex, uint256 toIndex) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        _transfer(from, to, expectedBalance[from]);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        _approve(owner, spender, amount);
    }

    /// @dev Explicitly exercise both revocation and unlimited allowances frequently.
    function setAllowanceBoundary(uint256 ownerIndex, uint256 spenderIndex, bool unlimited) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        _approve(owner, spender, unlimited ? type(uint256).max : 0);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, balance < allowanceBefore ? balance : allowanceBefore);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _recordTransfer(owner, to, amount);
        if (allowanceBefore != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function rejectOverdraw(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // All ghost state stays unchanged on failures; the invariants check every entry.
    }

    function rejectOverAllowance(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 amount;
        if (allowanceBefore == type(uint256).max) {
            // Unlimited approval is still constrained by the holder's balance.
            amount = type(uint256).max;
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
                )
            );
        } else {
            amount = allowanceBefore + 1;
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowanceBefore, amount
                )
            );
        }
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroReceiver(uint256 ownerIndex, uint256 spenderIndex, uint256 amount, bool delegated) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        uint256 available = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < available) {
            available = expectedAllowance[owner][spender];
        }
        amount = bound(amount, 0, available);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectDelegatedOverdraw(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex) external {
        address owner = actors[ownerIndex % actors.length];
        address spender = actors[spenderIndex % actors.length];
        address to = actors[toIndex % actors.length];
        uint256 amount = expectedBalance[owner] + 1;
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        if (allowanceBefore < amount) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowanceBefore, amount
                )
            );
        } else {
            // A finite allowance is spent before the balance check. Reverting must
            // roll it back, so the expected allowance deliberately remains unchanged.
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], amount
                )
            );
        }
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroSpender(uint256 ownerIndex, uint256 amount) external {
        address owner = actors[ownerIndex % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract GoatProInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    GoatPro internal token;
    GoatProHandler internal handler;

    function setUp() public {
        address initialHolder = makeAddr("invariant deployer");
        vm.prank(initialHolder);
        token = new GoatPro();
        handler = new GoatProHandler(token, initialHolder);

        // Fund every actor and seed both finite and infinite approvals through the
        // actual public API. No balance/allowance storage is patched by the harness.
        for (uint256 i = 1; i < 4; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }
        for (uint256 i; i < 4; ++i) {
            handler.approve(i, (i + 1) % 4, SUPPLY / 8);
        }
        handler.setAllowanceBoundary(0, 2, true);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = GoatProHandler.transfer.selector;
        selectors[1] = GoatProHandler.approve.selector;
        selectors[2] = GoatProHandler.transferFrom.selector;
        selectors[3] = GoatProHandler.transferEntireBalance.selector;
        selectors[4] = GoatProHandler.setAllowanceBoundary.selector;
        selectors[5] = GoatProHandler.rejectOverdraw.selector;
        selectors[6] = GoatProHandler.rejectOverAllowance.selector;
        selectors[7] = GoatProHandler.rejectZeroReceiver.selector;
        selectors[8] = GoatProHandler.rejectZeroSpender.selector;
        selectors[9] = GoatProHandler.rejectDelegatedOverdraw.selector;
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

    function invariant_BalancesAndAllowancesMatchAuthorizedCalls() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "holder balance differs from ledger");
            assertEq(token.allowance(owner, address(0)), 0, "zero address gained spending authority");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance differs from authorized approvals and spending"
                );
            }
        }
    }

    function invariant_MetadataAndUninvolvedAccountsStayUnchanged() public view {
        assertEq(token.name(), "GoatPro");
        assertEq(token.symbol(), "GPRO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    /// @dev After each random sequence, every holder must still be able to transfer
    /// its entire balance. This also checks recovery after any preceding failed call.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.transferEntireBalance(i, (i + 1) % 4);
        }
        invariant_SupplyAndSumOfBalancesStayConstant();
        invariant_BalancesAndAllowancesMatchAuthorizedCalls();
        invariant_MetadataAndUninvolvedAccountsStayUnchanged();
    }
}
