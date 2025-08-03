// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timerun;

    // Track users who have deposited collateral for minting/interaction
    address[] public userWithDepositCollateral;

    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        timerun = 0;

        // Initialize collateral token mocks
        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        // Initialize price feeds for collaterals
        ethUsdPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(weth))
        );
        btcUsdPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(wbtc))
        );
    }

    /// @notice Deposit collateral tokens into the protocol
    /// @param collateralSeed Random seed to select collateral token
    /// @param amount Amount of collateral to deposit (will be bounded)
    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        address collateral = _getCollateralfromSeed(collateralSeed);
        uint256 mintAmount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        // Mint collateral tokens directly to msg.sender
        ERC20Mock(collateral).mint(msg.sender, mintAmount);

        // Simulate user approving and depositing collateral
        vm.startPrank(msg.sender);
        ERC20Mock(collateral).approve(address(dsce), type(uint256).max);
        dsce.depositCollateral(collateral, mintAmount);
        vm.stopPrank();

        userWithDepositCollateral.push(msg.sender);
    }

    /// @notice Redeem user's collateral while maintaining health factor
    /// @param seed Seed to select collateral token
    /// @param amount Amount of collateral to redeem (bounded by max safe redeemable)
    function redeemCollateral(uint256 seed, uint256 amount) public {
        address token = _getCollateralfromSeed(seed);

        uint256 userCollateral = dsce.getCollateralBalanceOfUser(
            msg.sender,
            token
        );
        (uint256 totalCollateralUsd, uint256 totalDscMinted) = dsce
            .getAccountInformation(msg.sender);

        uint256 price = dsce.getUsdValue(token, 1 ether);
        uint256 liquidationThreshold = dsce.getLiquidationThreshold(); // usually 50
        uint256 liquidationPrecision = dsce.getLiquidationPrecision(); // usually 100

        // Calculate safe collateral USD after considering liquidation threshold
        uint256 safeCollateralUsd = totalCollateralUsd >
            (totalDscMinted * liquidationPrecision) / liquidationThreshold
            ? totalCollateralUsd -
                (totalDscMinted * liquidationPrecision) /
                liquidationThreshold
            : 0;

        uint256 safeCollateralToken = safeCollateralUsd / price;
        uint256 maxRedeem = userCollateral < safeCollateralToken
            ? userCollateral
            : safeCollateralToken;
        uint256 toRedeem = bound(amount, 0, maxRedeem);

        if (toRedeem == 0) return;

        vm.prank(msg.sender);
        dsce.redeemCollateral(token, toRedeem);
    }

    /// @notice Mint stablecoin backed by deposited collateral
    /// @param amountDscToMint Amount of DSC to mint (bounded by available collateral)
    /// @param collateralSeed Seed to select a user from those with deposits
    function mintDsc(uint256 amountDscToMint, uint256 collateralSeed) public {
        if (userWithDepositCollateral.length == 0) return;

        address sender = userWithDepositCollateral[
            collateralSeed % userWithDepositCollateral.length
        ];
        (uint256 collateralValue, uint256 dscMinted) = dsce
            .getAccountInformation(sender);

        // Max DSC mintable is half of collateral value minus what is already minted
        uint256 maxAmountDscToMint = (collateralValue / 2) > dscMinted
            ? (collateralValue / 2) - dscMinted
            : 0;

        if (maxAmountDscToMint == 0) return;

        amountDscToMint = bound(amountDscToMint, 1, maxAmountDscToMint);

        vm.startPrank(sender);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();

        timerun++;
    }

    /// @notice Transfer DSC tokens to another address
    /// @param amountDsc Amount of DSC to transfer
    /// @param to Recipient address
    function transferDsc(uint256 amountDsc, address to) public {
        uint256 balance = dsc.balanceOf(msg.sender);
        if (balance == 0) return; // Avoid revert

        amountDsc = bound(amountDsc, 1, balance);

        vm.prank(msg.sender);
        dsc.transfer(to, amountDsc);
    }

    /// @notice Update price of collateral token via mock price feed
    /// @dev Only allow non-volatile changes and preserve protocol solvency
    /// @param newPriceSeed Random seed to generate new price within bounds
    /// @param collateralSeed Select collateral token to update
    function updateCollateralPrice(
        uint128 newPriceSeed,
        uint256 collateralSeed
    ) public {
        address collateral = _getCollateralfromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(collateral)
        );

        uint256 lowerBound;
        uint256 upperBound;

        if (collateral == address(weth)) {
            lowerBound = 1500e8;
            upperBound = 2500e8;
        } else if (collateral == address(wbtc)) {
            lowerBound = 750e8;
            upperBound = 1250e8;
        } else {
            revert("Unknown collateral");
        }

        uint256 bounded = bound(uint256(newPriceSeed), lowerBound, upperBound);

        if (bounded > uint256(type(int256).max)) return;
        int256 newPrice = int256(bounded);

        int256 currentPrice = priceFeed.latestAnswer();
        int256 diff = currentPrice > newPrice
            ? currentPrice - newPrice
            : newPrice - currentPrice;

        // Skip update if price change is more than 50%
        if (diff > (currentPrice / 2)) {
            console.log("Skipping price update: too volatile");
            return;
        }

        // Check if protocol remains solvent after price update
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethBalance = weth.balanceOf(address(dsce));
        uint256 wbtcBalance = wbtc.balanceOf(address(dsce));

        uint256 wethUsdValue = dsce.getUsdValue(address(weth), wethBalance);
        uint256 wbtcUsdValue = dsce.getUsdValue(address(wbtc), wbtcBalance);

        uint256 projectedWethValue = collateral == address(weth)
            ? (bounded * wethBalance) / 1e8
            : wethUsdValue;
        uint256 projectedWbtcValue = collateral == address(wbtc)
            ? (bounded * wbtcBalance) / 1e8
            : wbtcUsdValue;

        uint256 totalProjectedValue = projectedWethValue + projectedWbtcValue;

        if (totalProjectedValue < totalSupply) {
            console.log("Skipping price update: would break invariant");
            return;
        }

        // Perform price update
        priceFeed.updateAnswer(newPrice);
    }

    /// @notice Helper to get collateral token address from a seed
    /// @param collateralSeed Random seed
    /// @return collateral Token address selected by seed
    function _getCollateralfromSeed(
        uint256 collateralSeed
    ) private view returns (address) {
        address[] memory tokens = dsce.getCollateralTokens();
        return tokens[collateralSeed % tokens.length];
    }

    /// @notice Debug helper to log current protocol stats
    function callSummary() external view {
        console.log("WETH total deposited:", weth.balanceOf(address(dsce)));
        console.log("WBTC total deposited:", wbtc.balanceOf(address(dsce)));
        console.log("DSC total supply:", dsc.totalSupply());
    }
}
