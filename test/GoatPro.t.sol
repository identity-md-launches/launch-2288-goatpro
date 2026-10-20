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
        vm.assume(recipient != address(0) && recipient != deployer);
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
}
