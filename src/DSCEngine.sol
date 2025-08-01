// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import "forge-std/console.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

// Errors
error DSCEngine__NeedsMoreThanZero();
error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch();
error DSCEngine__TokenNotAllowed(address token);
error DSCEngine__TransferFailed();
error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
error DSCEngine__HealthFactorOK();
error DSCEngine__HealthFactorNotImproved();
error DSCEngine__NotEnoughCollateralToRedeem();
contract DSCEngine is ReentrancyGuard {
    /*/////////////////////////////////////////////////////////////
                        TYPE DECLARATIONS
    /////////////////////////////////////////////////////////////*/

    using OracleLib for AggregatorV3Interface;

    /*/////////////////////////////////////////////////////////////
                         STATE VARIABLES
    /////////////////////////////////////////////////////////////*/
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralization
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    address[] private s_collateralTokens;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    DecentralizedStableCoin private immutable i_dsc;

    /*/////////////////////////////////////////////////////////////
                              EVENTS
    /////////////////////////////////////////////////////////////*/
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );
    event DscMinted(address indexed user, uint256 amount);
    event DscBurned(address indexed user, uint256 amount);

    /*/////////////////////////////////////////////////////////////
                             MODIFIERS
    /////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0))
            revert DSCEngine__TokenNotAllowed(token);
        _;
    }

    /*/////////////////////////////////////////////////////////////
                           CONSTRUCTOR
    /////////////////////////////////////////////////////////////*/
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch();
        }
        for (uint256 i; i < tokenAddresses.length; i++) {
            address token = tokenAddresses[i];
            address feed = priceFeedAddresses[i];

            if (token == address(0) || feed == address(0)) {
                revert DSCEngine__TokenNotAllowed(token);
            }
            s_priceFeeds[token] = feed;
            s_collateralTokens.push(token);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*/////////////////////////////////////////////////////////////
                           RECEIVE & FALLBACK
    /////////////////////////////////////////////////////////////*/
    // (not used)

    /*/////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////*/
    /// @notice Deposit collateral and mint DSC in a single call
    function depositCollateralAndMintDsc(
        address token,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(token, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateral(
        address token,
        uint256 amount
    ) external moreThanZero(amount) nonReentrant isAllowedToken(token) {
        _redeemCollateral(token, amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // function liquidate(
    //     address user,
    //     address collateralToken,
    //     uint256 debtToCover
    // ) external nonReentrant moreThanZero(debtToCover) {
    //     uint startingUserHealthFactor = _getHealthFactor(user);
    //     console.log("startingUserHealthFactor is ", startingUserHealthFactor);
    //     if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
    //         revert DSCEngine__HealthFactorOK();
    //     }

    //     uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
    //         collateralToken,
    //         debtToCover
    //     );

    //     uint256 bonusCollateral = (tokenAmountFromDebtCovered *
    //         LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
    //     uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
    //         bonusCollateral;

    //     _redeemCollateral(
    //         collateralToken,
    //         totalCollateralToRedeem,
    //         user,
    //         msg.sender
    //     );
    //     _burnDsc(debtToCover, user, msg.sender);

    //     uint256 endingUserHealthFactor = _getHealthFactor(user);
    //     // This conditional should never hit, but just in case
    //     if (endingUserHealthFactor <= startingUserHealthFactor) {
    //         revert DSCEngine__HealthFactorNotImproved();
    //     }
    //     _revertIfHealthFactorIsBroken(msg.sender);
    // }
    function liquidate(
        address user,
        address collateralToken,
        uint256 debtToCover
    ) external nonReentrant moreThanZero(debtToCover) {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        console.log("hf is ", startingUserHealthFactor);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        console.log("afhter if ");

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateralToken,
            debtToCover
        );
        console.log("tokenAmountFromDebtCovered", tokenAmountFromDebtCovered);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        console.log("bonusCollateral", bonusCollateral);

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        console.log("totalCollateralToRedeem", totalCollateralToRedeem);

        uint256 userCollateralBalance = s_collateralDeposited[user][
            collateralToken
        ];
        if (userCollateralBalance < totalCollateralToRedeem) {
            revert DSCEngine__NotEnoughCollateralToRedeem();
        }
        _redeemCollateral(
            collateralToken,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        console.log("go");
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _getHealthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateralForDsc(
        address token,
        uint256 collateralAmount,
        uint256 dscToBurn
    ) external {
        // Call internal implementations directly to avoid external call overhead and reentrancy concerns
        _burnDsc(dscToBurn, msg.sender, msg.sender);
        _redeemCollateral(token, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    /*/////////////////////////////////////////////////////////////
                         PUBLIC FUNCTIONS
    /////////////////////////////////////////////////////////////*/
    function depositCollateral(
        address token,
        uint256 amount
    ) public moreThanZero(amount) isAllowedToken(token) nonReentrant {
        s_collateralDeposited[msg.sender][token] += amount;
        emit CollateralDeposited(msg.sender, token, amount);

        bool success = IERC20(token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert DSCEngine__TransferFailed();
    }

    function mintDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);

        i_dsc.mint(msg.sender, amount);
        emit DscMinted(msg.sender, amount);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalValue) {
        for (uint256 i; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalValue += getUsdValue(token, amount);
        }
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmount
    ) public view returns (uint256) {
        address feed = s_priceFeeds[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        uint256 tokenPriceInUsd = uint256(price) * ADDITIONAL_FEED_PRECISION;
        return (usdAmount * PRECISION) / tokenPriceInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        address feed = s_priceFeeds[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        console.log("price is ", price);
        uint256 adjustedPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        console.log("adjusted price is ", adjustedPrice);
        return (amount * adjustedPrice) / PRECISION;
    }

    function getAccountInformation(
        address user
    ) public view returns (uint256 collateralValue, uint256 dscMinted) {
        (collateralValue, dscMinted) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }
    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /*/////////////////////////////////////////////////////////////
                             INTERNAL & PRIVATE
    /////////////////////////////////////////////////////////////*/

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(
        address user
    ) internal view returns (uint256 collateralValue, uint256 dscMinted) {
        collateralValue = getAccountCollateralValue(user);
        dscMinted = s_DSCMinted[user];
    }

    function _getHealthFactor(address user) private view returns (uint256) {
        (
            uint256 collateralValueInUsd,
            uint256 totalDscMinted
        ) = _getAccountInformation(user);
        console.log(
            "collateralValueInUsd in healfactor is ",
            collateralValueInUsd
        );
        console.log("totalDscMinted is ", totalDscMinted);
        return _calculateHealthFactor(collateralValueInUsd, totalDscMinted);
    }

    function _calculateHealthFactor(
        uint256 totalCollateralValue,
        uint256 totalDscMinted
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        return
            ((totalCollateralValue * LIQUIDATION_THRESHOLD * PRECISION) /
                LIQUIDATION_PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 hf = _getHealthFactor(user);
        if (hf < MIN_HEALTH_FACTOR) revert DSCEngine__BreaksHealthFactor(hf);
    }
}
