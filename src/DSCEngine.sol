// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Imports
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @notice The core engine of the Decentralized StableCoin system
 * @dev This contract handles all the core logic including:
 * - Collateral deposits and redemptions
 * - DSC minting and burning
 * - Liquidation of undercollateralized positions
 * - Health factor calculations
 */
contract DSCEngine is ReentrancyGuard {
    /*/////////////////////////////////////////////////////////////
                                TYPES
    /////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*/////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////*/
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    // Liquidation parameters
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralization
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /*/////////////////////////////////////////////////////////////
                            STATE VARIABLES
    /////////////////////////////////////////////////////////////*/
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
                                ERRORS
    /////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__NotEnoughCollateralToRedeem();
    error DSCEngine__MintFailed();

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

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
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
                         EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit collateral and mint DSC in a single transaction
     * @param token The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address token,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(token, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice Redeem collateral for a user
     * @param token The address of the collateral token to redeem
     * @param amount The amount of collateral to redeem
     */
    function redeemCollateral(
        address token,
        uint256 amount
    ) external moreThanZero(amount) nonReentrant isAllowedToken(token) {
        _redeemCollateral(token, amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Burn DSC tokens
     * @param amount The amount of DSC to burn
     */
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param user The address of the user to liquidate
     * @param collateralToken The collateral token to liquidate
     * @param debtToCover The amount of DSC debt to cover
     */
    function liquidate(
        address user,
        address collateralToken,
        uint256 debtToCover
    ) external nonReentrant moreThanZero(debtToCover) {
        uint256 startingUserHealthFactor = _getHealthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateralToken,
            debtToCover
        );
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

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
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _getHealthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Redeem collateral and burn DSC in a single transaction
     * @param token The collateral token to redeem
     * @param collateralAmount The amount of collateral to redeem
     * @param dscToBurn The amount of DSC to burn
     */
    function redeemCollateralForDsc(
        address token,
        uint256 collateralAmount,
        uint256 dscToBurn
    ) external {
        _burnDsc(dscToBurn, msg.sender, msg.sender);
        _redeemCollateral(token, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*/////////////////////////////////////////////////////////////
                         PUBLIC FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit collateral into the system
     * @param token The address of the collateral token
     * @param amount The amount of collateral to deposit
     */
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

    /**
     * @notice Mint DSC tokens
     * @param amount The amount of DSC to mint
     */
    function mintDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
        s_DSCMinted[msg.sender] += amount;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amount);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
        emit DscMinted(msg.sender, amount);
    }

    /*/////////////////////////////////////////////////////////////
                         VIEW/PURE FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the USD value of a user's collateral
     * @param user The address of the user
     * @return totalValue The total USD value of the user's collateral
     */
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalValue += getUsdValue(token, amount);
        }
    }

    /**
     * @notice Convert USD amount to token amount
     * @param token The token address
     * @param usdAmount The USD amount to convert
     * @return The equivalent token amount
     */
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        uint256 tokenPriceInUsd = uint256(price) * ADDITIONAL_FEED_PRECISION;
        return (usdAmount * PRECISION) / tokenPriceInUsd;
    }

    /**
     * @notice Calculate the USD value of a token amount
     * @param token The token address
     * @param amount The token amount
     * @return The USD value of the token amount
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        uint256 adjustedPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
        return (amount * adjustedPrice) / PRECISION;
    }

    /**
     * @notice Get account information (collateral value and DSC minted)
     * @param user The user address
     * @return collateralValue The total collateral value in USD
     * @return dscMinted The amount of DSC minted by the user
     */
    function getAccountInformation(
        address user
    ) public view returns (uint256 collateralValue, uint256 dscMinted) {
        (collateralValue, dscMinted) = _getAccountInformation(user);
    }

    /**
     * @notice Calculate the health factor of a user
     * @param user The user address
     * @return The health factor value
     */
    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    // Getter functions for constants and state variables
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
    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    /*/////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////////*/

    /**
     * @dev Redeem collateral from the system
     * @param tokenCollateralAddress The collateral token address
     * @param amountCollateral The amount to redeem
     * @param from The address to redeem from
     * @param to The address to send the redeemed collateral to
     */
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
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @dev Burn DSC tokens
     * @param amountDscToBurn The amount of DSC to burn
     * @param onBehalfOf The address whose DSC is being burned
     * @param dscFrom The address providing the DSC tokens
     */
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
        if (!success) revert DSCEngine__TransferFailed();

        i_dsc.burn(amountDscToBurn);
    }

    /**
     * @dev Get account information (internal version)
     * @param user The user address
     * @return collateralValue The total collateral value in USD
     * @return dscMinted The amount of DSC minted by the user
     */
    function _getAccountInformation(
        address user
    ) internal view returns (uint256 collateralValue, uint256 dscMinted) {
        collateralValue = getAccountCollateralValue(user);
        dscMinted = s_DSCMinted[user];
    }

    /**
     * @dev Calculate the health factor for a user
     * @param user The user address
     * @return The health factor value
     */
    function _getHealthFactor(address user) private view returns (uint256) {
        (
            uint256 collateralValueInUsd,
            uint256 totalDscMinted
        ) = _getAccountInformation(user);
        return _calculateHealthFactor(collateralValueInUsd, totalDscMinted);
    }

    /**
     * @dev Calculate the health factor from collateral and debt values
     * @param totalCollateralValue The total collateral value in USD
     * @param totalDscMinted The total DSC minted
     * @return The calculated health factor
     */
    function _calculateHealthFactor(
        uint256 totalCollateralValue,
        uint256 totalDscMinted
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        return
            ((totalCollateralValue * LIQUIDATION_THRESHOLD * PRECISION) /
                LIQUIDATION_PRECISION) / totalDscMinted;
    }

    /**
     * @dev Revert if the user's health factor is broken
     * @param user The user address to check
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 hf = _getHealthFactor(user);
        if (hf < MIN_HEALTH_FACTOR) revert DSCEngine__BreaksHealthFactor(hf);
    }
}
