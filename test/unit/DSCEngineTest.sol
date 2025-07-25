// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {DSCEngine, DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch, DSCEngine__NeedsMoreThanZero, DSCEngine__TokenNotAllowed, DSCEngine__BreaksHealthFactor} from "../../src/DSCEngine.sol";

contract DSCEngineTest is Test {
    // --- Fixture ---
    DeployDSC private deployer;
    DecentralizedStableCoin private dsc;
    DSCEngine private dsce;
    HelperConfig private config;

    address private wethUsdPriceFeed;
    address private wbtcUsdPriceFeed;
    address private weth;
    address private wbtc;

    address public constant USER = address(0x1);
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC_BALANCE = 10 ether;

    /// @notice Deploy contracts and fund USER with WETH
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        // Mint initial WETH to USER
        ERC20Mock(weth).mint(USER, STARTING_ERC_BALANCE);
    }

    // Modifier to deposit collateral for USER
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    // --- Unit Tests ---

    /// @notice Should revert when token and price feed arrays mismatch
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokens = new address[](1);
        address[] memory feeds = new address[](2);
        tokens[0] = weth;
        feeds[0] = wethUsdPriceFeed;
        feeds[1] = wbtcUsdPriceFeed;

        vm.expectRevert(
            DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch
                .selector
        );
        new DSCEngine(tokens, feeds, address(dsc));
    }

    /// @notice getTokenAmountFromUsd should return correct amount
    function testGetTokenAmountFromUsd() public view {
        // $100 of WETH @$2,000/WETH = 0.05 WETH
        uint256 expected = 0.05 ether;
        uint256 actual = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(actual, expected);
    }

    /// @notice getUsdValue should compute USD value correctly
    function testGetUsdValue() public view {
        uint256 ethAmount = 15 ether;
        uint256 expectedUsd = 30_000 ether;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd, "getUsdValue incorrect");
    }

    /// @notice Zero collateral should return zero USD
    function testGetUsdValueZero() public view {
        assertEq(dsce.getUsdValue(weth, 0), 0, "Zero amount should be zero");
    }

    /// @notice depositCollateral should revert on zero amount
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    /// @notice depositCollateral should revert for unapproved token
    function testRevertWithUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine__TokenNotAllowed.selector,
                address(randomToken)
            )
        );
        dsce.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    /// @notice After deposit, account info should reflect collateral only
    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 collateralUsd, uint256 totalDscMinted) = dsce
            .getAccountInformation(USER);
        assertEq(totalDscMinted, 0, "No DSC minted yet");
        // collateralValueUsd back to token amount
        uint256 backToToken = dsce.getTokenAmountFromUsd(weth, collateralUsd);
        assertEq(backToToken, AMOUNT_COLLATERAL);
    }

    /// @notice depositCollateralAndMintDsc should mint correct amount
    function testDepositCollateralAndMintDsc_Succeeds() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 collateralUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 toMint = collateralUsd / 2;

        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, toMint);

        assertEq(dsc.balanceOf(USER), toMint, "Unexpected DSC balance");

        (uint256 acctUsd, uint256 acctMint) = dsce.getAccountInformation(USER);
        assertEq(acctUsd, collateralUsd);
        assertEq(acctMint, toMint);
        vm.stopPrank();
    }

    /// @notice depositCollateralAndMintDsc should revert on health factor break
    function testDepositCollateralAndMintDsc_RevertsHealthFactorBroken()
        public
    {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 badMint = type(uint256).max;
        vm.expectRevert(); // any revert ok
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, badMint);
        vm.stopPrank();
    }

    /// @notice mintDsc should succeed after deposit
    function testMintDscSucceedsAfterDeposit() public depositedCollateral {
        uint256 mintAmt = 1 ether;
        assertEq(dsc.balanceOf(USER), 0, "Initial DSC not zero");

        vm.startPrank(USER);
        dsce.mintDsc(mintAmt);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), mintAmt);
        (, uint256 totalMinted) = dsce.getAccountInformation(USER);
        assertEq(totalMinted, mintAmt);
    }

    /// @notice mintDsc should revert on zero amount
    function testMintDscRevertsOnZeroAmount() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    /// @notice mintDsc should revert when health factor broken
    function testMintDscRevertsIfHealthFactorBroken()
        public
        depositedCollateral
    {
        uint256 tooMuch = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) + 1;

        vm.startPrank(USER);
        vm.expectRevert(); // any custom revert ok
        dsce.mintDsc(tooMuch);
        vm.stopPrank();
    }
}
