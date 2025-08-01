// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timerun;

    address[] userWithDepositCollateral;

    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        timerun = 0;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(weth))
        );
    }

    // redeem collateral

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        address collateral = _getCollateralfromSeed(collateralSeed);
        uint256 mintAmount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        // Mint tokens to msg.sender not this contract!
        ERC20Mock(collateral).mint(msg.sender, mintAmount);

        // Prank so msg.sender approves
        vm.startPrank(msg.sender);
        ERC20Mock(collateral).approve(address(dsce), type(uint256).max);
        dsce.depositCollateral(collateral, mintAmount);
        userWithDepositCollateral.push(msg.sender);
        vm.stopPrank();
    }


    function redeemCollateral(uint256 seed, uint256 amount) public {
        address token = _getCollateralfromSeed(seed);

        uint256 userCollateral = dsce.getCollateralBalanceOfUser(
            msg.sender,
            token
        );

        (uint256 totalCollateralUsd, uint256 totalDscMinted) = dsce
            .getAccountInformation(msg.sender);
        uint256 price = dsce.getUsdValue(token, 1 ether);
        uint256 liquidationThreshold = dsce.getLiquidationThreshold(); // = 50
        uint256 liquidationPrecision = dsce.getLiquidationPrecision(); // = 100
        //    totalCollateralUsd – ( totalDscMinted × 1e18 / liquidationThreshold )
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

    function mintDsc(uint256 amountDscTomint, uint256 collateralSeed) public {
        if (userWithDepositCollateral.length == 0) {
            return;
        }

        address sender = userWithDepositCollateral[
            collateralSeed % userWithDepositCollateral.length
        ];

        (uint256 collateralValue, uint256 dscMinted) = dsce
            .getAccountInformation(sender);

        uint256 maxAmountDscToMint = (collateralValue / 2) - dscMinted;
        console.log(" collateralValue is :", collateralValue);
        console.log(" dscMinted is :", dscMinted);
        console.log(" maxAmountDscToMint is :", maxAmountDscToMint);

        if (maxAmountDscToMint <= 0) {
            return;
        }

        amountDscTomint = bound(amountDscTomint, 1, maxAmountDscToMint);
        console.log(" amountDscTomint is :", amountDscTomint);
        vm.startPrank(sender);
        dsce.mintDsc(amountDscTomint);
        vm.stopPrank();
        timerun++;
    }

    // function updateCollateralPrice(
    //     uint128,
    //     /* newPrice */ uint256 collateralSeed
    // ) public {
    //     // int256 intNewPrice = int256(uint256(newPrice));
    //     int256 intNewPrice = 0;
    //     MockV3Aggregator priceFeed = MockV3Aggregator(
    //         dscEngine.getCollateralTokenPriceFeed(_getCollateralfromSeed(collateralSeed));
    //     );

    //     priceFeed.updateAnswer(intNewPrice);
    // }

    function _getCollateralfromSeed(
        uint256 collateralSeed
    ) private view returns (address) {
        address collateral = dsce.getCollateralTokens()[
            collateralSeed % dsce.getCollateralTokens().length
        ];

        return collateral;
    }
}
