// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import "../../src/DSCEngine.sol";

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
    address public liquidator = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_TO_COVER = 100 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    uint256 amountToMint = 10000e18; // 10 * 2000 = 20000e18  and we can mint 20000e18/2 = 10000e18

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

    address[] public tokenAddresses;
    address[] public feedAddresses;

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
    function testRedeemCollateralWithValidAmount() public depositedCollateral {
        // Get initial USD value of collateral
        (uint256 initialCollateralUsd, ) = dsce.getAccountInformation(USER);

        uint256 redeemAmount = 1 ether;
        // Calculate USD value of the redeemed amount
        uint256 redeemAmountUsd = dsce.getUsdValue(weth, redeemAmount);

        vm.startPrank(USER);
        dsce.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();

        // Get final USD value of collateral
        (uint256 finalCollateralUsd, ) = dsce.getAccountInformation(USER);

        // Compare USD values
        assertEq(finalCollateralUsd, initialCollateralUsd - redeemAmountUsd);

        // Check token balance
        assertEq(
            ERC20Mock(weth).balanceOf(USER),
            STARTING_ERC_BALANCE - AMOUNT_COLLATERAL + redeemAmount
        );
    }

    /// @notice Should revert when token is not allowed
    function testRedeemCollateralRevertsOnInvalidToken()
        public
        depositedCollateral
    {
        address invalidToken = address(0x123);

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine__TokenNotAllowed.selector,
                invalidToken
            )
        );
        dsce.redeemCollateral(invalidToken, 1 ether);
        vm.stopPrank();
    }

    /// @notice Should revert when amount exceeds deposited collateral
    function testRedeemCollateralRevertsOnExcessiveAmount()
        public
        depositedCollateral
    {
        uint256 excessiveAmount = AMOUNT_COLLATERAL + 1 ether;

        vm.startPrank(USER);
        vm.expectRevert();
        dsce.redeemCollateral(weth, excessiveAmount);
        vm.stopPrank();
    }

    // BurnDsc test
    function testBurnDscSuccessfully() public depositedCollateral {
        uint256 mintAmount = 5 ether;
        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        vm.prank(USER);
        dsc.approve(address(dsce), mintAmount);

        uint256 initialDscBalance = dsc.balanceOf(USER);
        (, uint256 initialDscMinted) = dsce.getAccountInformation(USER);

        // burn DSC
        uint256 burnAmount = 2 ether;
        vm.startPrank(USER);
        dsce.burnDsc(burnAmount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), initialDscBalance - burnAmount);
        (, uint256 newDscAmount) = dsce.getAccountInformation(USER);
        assertEq(newDscAmount, initialDscMinted - burnAmount);
    }

    function testBurnDscRevertsIfNotEnoughDsc() public depositedCollateral {
        uint256 mintAmount = 1 ether;
        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        vm.prank(USER);
        dsc.approve(address(dsce), mintAmount);

        vm.startPrank(USER);
        vm.expectRevert(); // ERC20: transfer amount exceeds balance
        dsce.burnDsc(mintAmount + 1 ether);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfNotApproved() public depositedCollateral {
        uint256 mintAmount = 1 ether;
        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        vm.startPrank(USER);
        vm.expectRevert(); // ERC20: insufficient allowance
        dsce.burnDsc(mintAmount);
        vm.stopPrank();
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testMustImproveHealthFactorOnLiquidation() public {
        // Arrange - Setup
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(wethUsdPriceFeed);
        tokenAddresses = [weth];
        feedAddresses = [wethUsdPriceFeed];
        address owner = msg.sender;

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            feedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateralAndMintDsc(
            weth,
            AMOUNT_COLLATERAL,
            amountToMint
        );
        vm.stopPrank();

        (uint256 collateral, uint256 dscMinted) = mockDsce
            .getAccountInformation(USER);
        console.log("user collateral: ", collateral);
        console.log("user DSC minted: ", dscMinted);

        uint256 COLLATERAL_TO_COVERInThisTest = 1 ether;
        uint256 safeAmountToMint = 500 * 1e18;
        uint256 debtToCover = 400 * 1e18;

        ERC20Mock(weth).mint(liquidator, COLLATERAL_TO_COVERInThisTest);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(
            address(mockDsce),
            COLLATERAL_TO_COVERInThisTest
        );
        mockDsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVERInThisTest,
            safeAmountToMint
        );
        mockDsc.approve(address(mockDsce), debtToCover);

        int256 ethUsdUpdatedPrice = 1800e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        vm.expectRevert(DSCEngine__HealthFactorNotImproved.selector);
        mockDsce.liquidate(USER, weth, debtToCover);
        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateral {
        ERC20Mock(weth).mint(liquidator, COLLATERAL_TO_COVER);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVER,
            amountToMint
        );
        dsc.approve(address(dsce), amountToMint);

        vm.expectRevert(DSCEngine__HealthFactorOK.selector);
        dsce.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    /// @notice Modifier to deposit, mint and then liquidate USER position
    modifier liquidated() {
        // 1) USER deposits collateral & mints DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        // 2) Price drops to trigger liquidation
        int256 lowPrice = 1800e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(lowPrice);
        uint256 health = dsce.getHealthFactor(USER);
        console.log("Post-drop health factor:", health);

        // ensure under-collateralized
        assertTrue(health < dsce.getMinHealthFactor());

        ERC20Mock(weth).mint(liquidator, COLLATERAL_TO_COVER);

        // 3) LIQUIDATOR covers part of USER debt
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_TO_COVER,
            amountToMint
        );
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(USER, weth, amountToMint);
        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        // Check LIQUIDATOR received correct WETH
        uint256 received = ERC20Mock(weth).balanceOf(liquidator);
        uint256 expectedCollateral = dsce.getTokenAmountFromUsd(
            weth,
            amountToMint
        );
        uint256 bonus = (expectedCollateral * dsce.getLiquidationBonus()) /
            dsce.getLiquidationPrecision();
        uint256 expected = expectedCollateral + bonus;
        assertEq(received, expected);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dsce.getTokenAmountFromUsd(
            weth,
            amountToMint
        ) +
            ((dsce.getTokenAmountFromUsd(weth, amountToMint) *
                dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());

        uint256 usdAmountLiquidated = dsce.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        ) - (usdAmountLiquidated);

        (uint256 userCollateralValueInUsd, ) = dsce.getAccountInformation(USER);
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (, uint256 liquidatorDscMinted) = dsce.getAccountInformation(
            liquidator
        );
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (, uint256 userDscMinted) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    // ///////////////////////////////////
    // // View & Pure Function Tests //
    // //////////////////////////////////

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, wethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view{
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view{
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation()
        public
        depositedCollateral
    {
        ( uint256 collateralValue,) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public view{
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public view{
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
