// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {GoatPro} from "../src/GoatPro.sol";

/// @dev A local factory model; it is not a production deployment contract.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (GoatPro) {
        return new GoatPro{salt: salt}();
    }

    function distribute(GoatPro token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// forge-config: default.fuzz.runs = 1000
contract GoatProTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    GoatPro internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        vm.prank(deployer);
        token = new GoatPro();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "GoatPro");
        assertEq(token.symbol(), "GPRO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        vm.prank(alice);
        GoatPro another = new GoatPro();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(another));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(another.balanceOf(alice), SUPPLY);
    }

    function test_Create2FactoryReceivesSupplyAndLaunchTransfersAreExact() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        vm.prank(deployer);
        GoatPro launched = factory.deploy(keccak256("GPRO launch test"));
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");

        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(deployer), 0);
        assertEq(launched.balanceOf(address(this)), 0);

        // Model the launch's token movements, with no tax or transfer exemption.
        factory.distribute(launched, distributor, SUPPLY / 10);
        factory.distribute(launched, pool, SUPPLY * 8 / 10);
        factory.distribute(launched, deployer, SUPPLY / 10);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(deployer), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), SUPPLY / 10);

        vm.prank(pool);
        assertTrue(launched.transfer(bob, 123 ether));
        assertEq(launched.balanceOf(bob), 123 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 123 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 42 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 42 ether));
        assertEq(token.balanceOf(alice), 42 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 42 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireBalanceCanBeTransferred() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroAlsoReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);
    }

    function test_InsufficientBalanceRevertsWithoutChangingBalances() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ApproveEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.startPrank(deployer);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 100 ether);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(deployer, spender), 100 ether);
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(deployer, spender), 7 ether);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 100);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 40 ether));
        assertEq(token.allowance(deployer, spender), 60 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(spender), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 60 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_InfiniteAllowanceIsNotDecreased() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_UnapprovedSpenderCannotMoveTokens() public {
        vm.prank(deployer);
        token.approve(spender, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(deployer, spender), 1 ether);
    }

    function test_InsufficientAllowanceRevertsWithoutSpendingIt() public {
        vm.prank(deployer);
        token.approve(spender, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5, 6));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 6);
        assertEq(token.allowance(deployer, spender), 5);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 50));
        vm.prank(spender);
        token.transferFrom(alice, bob, 50);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToZeroRestoresAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 50);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderRevertsEvenForZeroAmount() public {
        // Allowance spending validates the owner before the transfer is reached.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_TransferFromZeroAmountNeedsNoApproval() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfConsumesAllowanceButPreservesBalance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 40));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), 60);
    }

    function test_DeployerCannotSeizeHolderTokens() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[10] = abi.encodeWithSignature("initialize(address)", alice);
        calls[11] = abi.encodeWithSignature("setMinter(address)", alice);
        vm.prank(deployer);
        token.transfer(alice, 100);

        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached unexpected entry point");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger reached unexpected entry point");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY - 100);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_RuntimeHasNoPrivilegedExecutionOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        if (recipient == deployer) recipient = alice;
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferMoreThanSupplyReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_TransferFromRespectsApproval(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromRejectsOverspending(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, amount);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_OneWeiAllowanceCannotBeReusedAfterTokensReturn() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(deployer, spender), 0);

        vm.prank(alice);
        assertTrue(token.transfer(deployer, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OneBelowMaximumAllowanceIsFinite() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_UnlimitedAllowanceCanBeRevokedAndReplacedWithFiniteAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.prank(deployer);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(deployer, spender), 0);

        vm.prank(deployer);
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 2));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(deployer), SUPPLY - 3);
    }

    function test_HolderNeedsSelfApprovalForTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(deployer);
        assertTrue(token.approve(deployer, 1));
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_DelegatedTransferToSpenderCreditsOnlyOnce() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, 10));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), 10);
        assertEq(token.balanceOf(deployer), SUPPLY - 10);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumUintTransferFailsEvenWithUnlimitedApproval() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);

        vm.prank(deployer);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroReceiverReverts() public {
        vm.prank(deployer);
        assertTrue(token.approve(spender, 5));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 0);
        assertEq(token.allowance(deployer, spender), 5);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(0), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalFromAnotherOwnerDoesNotAuthorizeSpending() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 10));
        vm.prank(deployer);
        assertTrue(token.approve(spender, 10));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 10));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(deployer, spender), 10);
        assertEq(token.allowance(alice, spender), 0);
    }

    function testFuzz_TransferRoundTripPreservesBalancesAndApprovals(
        uint256 startingBalance,
        uint256 amount,
        uint256 approved
    ) public {
        startingBalance = bound(startingBalance, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - startingBalance);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, startingBalance));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), startingBalance + amount);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, amount));

        assertEq(token.balanceOf(deployer), SUPPLY - startingBalance);
        assertEq(token.balanceOf(alice), startingBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersMatchSingleTransfer(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        vm.prank(deployer);
        GoatPro singleTransferToken = new GoatPro();

        vm.startPrank(deployer);
        assertTrue(singleTransferToken.transfer(alice, amount));
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, amount - first));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), singleTransferToken.balanceOf(alice));
        assertEq(token.balanceOf(deployer), singleTransferToken.balanceOf(deployer));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransferToken.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement) public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 100));
        vm.startPrank(deployer);
        assertTrue(token.approve(bob, 42));
        assertTrue(token.approve(spender, first));
        vm.stopPrank();
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));

        vm.startPrank(deployer);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(deployer, spender), replacement);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, replacement);
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();

        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.allowance(deployer, bob), 42);
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.allowance(spender, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 100);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedBalanceFailureIsAtomicAndAllowanceRemainsUsable(
        uint256 held,
        uint256 amount,
        uint256 approved
    ) public {
        held = bound(held, 1, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        approved = bound(approved, amount, type(uint256).max);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, held));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), held);
        assertEq(token.balanceOf(deployer), SUPPLY - held);
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferCannotBypassBalanceCheck(uint256 held, uint256 amount, bool delegated) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        if (delegated) {
            vm.prank(alice);
            assertTrue(token.approve(spender, type(uint256).max));
        }

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(alice, alice, amount);
        } else {
            vm.prank(alice);
            token.transfer(alice, amount);
        }
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(deployer), SUPPLY - held);
        assertEq(token.allowance(alice, spender), delegated ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FiniteAllowanceLimitsCumulativeSpending(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY - 1);
        first = bound(first, 0, approved);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, first));
        assertEq(token.allowance(deployer, spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, approved - first));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, spender, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), approved - first);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedZeroReceiverFailurePreservesFiniteAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max - 1);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), approved);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, spender), approved - amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferConsumesFiniteAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max - 1);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, amount));
        assertEq(token.allowance(deployer, spender), approved - amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
