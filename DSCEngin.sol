diff --git a/src/DSCEngine.sol b/src/DSCEngine.sol
index f339206..6dc824f 100644
--- a/src/DSCEngine.sol
+++ b/src/DSCEngine.sol
@@ -23,56 +23,68 @@
 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.18;
 
-import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
+// Imports
 import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
 import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
 import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
+import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
+import "forge-std/console.sol";
+
+// Errors
+error DSCEngine__NeedsMoreThanZero();
+error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch();
+error DSCEngine__TokenNotAllowed(address token);
+error DSCEngine__TransferFailed();
+error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
+error DSCEngine__HealthFactorOK();
+error DSCEngine__HealthFactorNotImproved();
 contract DSCEngine is ReentrancyGuard {
-    ///////////////////
-    // Errors
-    ///////////////////
-
-    error DSCEngine__NeedsMoreThanZero();
-    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch();
-    error DSCEngine__TokenNotAllowed(address token);
-    error DSCEngine__TransferFailed();
-    error DSCEngine__transferFailed();
-    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
-
-    ///////////////////
-    // State Variables
-    ///////////////////
-
-    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
-    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
-    uint256 private constant LIQUIDATION_PRECISION = 100;
-    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
+    /*/////////////////////////////////////////////////////////////
+                        TYPE DECLARATIONS
+    /////////////////////////////////////////////////////////////*/
+
+    // (no custom types)
+
+    /*/////////////////////////////////////////////////////////////
+                         STATE VARIABLES
+    /////////////////////////////////////////////////////////////*/
     uint256 private constant PRECISION = 1e18;
     uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
     uint256 private constant FEED_PRECISION = 1e8;
 
+    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralization
+    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
+    uint256 private constant LIQUIDATION_PRECISION = 100;
+    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
+
+    address[] private s_collateralTokens;
     mapping(address token => address priceFeed) private s_priceFeeds;
-    mapping(address user => mapping(address collateralToken => uint256 amount))
+    mapping(address user => mapping(address token => uint256 amount))
         private s_collateralDeposited;
     mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
 
-    address[] private s_collateralTokens;
     DecentralizedStableCoin private immutable i_dsc;
 
-    ///////////////////
-    // Events
-    ///////////////////
-
+    /*/////////////////////////////////////////////////////////////
+                              EVENTS
+    /////////////////////////////////////////////////////////////*/
     event CollateralDeposited(
         address indexed user,
         address indexed token,
-        uint256 indexed amount
+        uint256 amount
     );
+    event CollateralRedeemed(
+        address indexed redeemFrom,
+        address indexed redeemTo,
+        address indexed token,
+        uint256 amount
+    );
+    event DscMinted(address indexed user, uint256 amount);
+    event DscBurned(address indexed user, uint256 amount);
 
-    ///////////////////
-    // Modifiers
-    ///////////////////
-
+    /*/////////////////////////////////////////////////////////////
+                             MODIFIERS
+    /////////////////////////////////////////////////////////////*/
     modifier moreThanZero(uint256 amount) {
         if (amount == 0) revert DSCEngine__NeedsMoreThanZero();
         _;
@@ -84,10 +96,9 @@ contract DSCEngine is ReentrancyGuard {
         _;
     }
 
-    ///////////////////
-    // Constructor
-    ///////////////////
-
+    /*/////////////////////////////////////////////////////////////
+                           CONSTRUCTOR
+    /////////////////////////////////////////////////////////////*/
     constructor(
         address[] memory tokenAddresses,
         address[] memory priceFeedAddresses,
@@ -96,122 +107,226 @@ contract DSCEngine is ReentrancyGuard {
         if (tokenAddresses.length != priceFeedAddresses.length) {
             revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsDontMatch();
         }
-        for (uint256 i = 0; i < tokenAddresses.length; i++) {
+        for (uint256 i; i < tokenAddresses.length; i++) {
             address token = tokenAddresses[i];
             address feed = priceFeedAddresses[i];
+
             if (token == address(0) || feed == address(0)) {
                 revert DSCEngine__TokenNotAllowed(token);
             }
             s_priceFeeds[token] = feed;
-            // Use push instead of direct indexing to avoid out-of-bounds
             s_collateralTokens.push(token);
         }
         i_dsc = DecentralizedStableCoin(dscAddress);
     }
 
-    ///////////////////
-    // External Functions
-    ///////////////////
+    /*/////////////////////////////////////////////////////////////
+                           RECEIVE & FALLBACK
+    /////////////////////////////////////////////////////////////*/
+    // (not used)
 
-    // واریز وثیقه توسط کاربر
-    function depositCollateral(
+    /*/////////////////////////////////////////////////////////////
+                         EXTERNAL FUNCTIONS
+    /////////////////////////////////////////////////////////////*/
+    /// @notice Deposit collateral and mint DSC in a single call
+    function depositCollateralAndMintDsc(
         address token,
-        uint256 amount
-    ) external moreThanZero(amount) isAllowedToken(token) nonReentrant {
-        s_collateralDeposited[msg.sender][token] += amount;
-        emit CollateralDeposited(msg.sender, token, amount);
-
-        bool success = IERC20(token).transferFrom(
-            msg.sender,
-            address(this),
-            amount
-        );
-        if (!success) revert DSCEngine__transferFailed();
+        uint256 amountCollateral,
+        uint256 amountDscToMint
+    ) external {
+        depositCollateral(token, amountCollateral);
+        mintDsc(amountDscToMint);
     }
 
-    function redeemCollateral(address token, uint256 amount) external {}
-
-    function mintDsc(
+    function redeemCollateral(
+        address token,
         uint256 amount
     ) external moreThanZero(amount) nonReentrant {
-        s_DSCMinted[msg.sender] += amount;
+        _redeemCollateral(token, amount, msg.sender, msg.sender);
         _revertIfHealthFactorIsBroken(msg.sender);
-
-        i_dsc.mint(msg.sender, amount);
     }
 
-    function burnDsc(uint256 amount) external {}
+    function burnDsc(uint256 amount) external moreThanZero(amount) {
+        _burnDsc(amount, msg.sender, msg.sender);
+        _revertIfHealthFactorIsBroken(msg.sender);
+    }
 
     function liquidate(
         address user,
         address collateralToken,
         uint256 debtToCover
-    ) external {}
+    ) external nonReentrant moreThanZero(debtToCover) {
+        uint startingUserHealthFactor = _getHealthFactor(user);
+        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
+            revert DSCEngine__HealthFactorOK();
+        }
 
-    ///////////////////////////////
-    // Private & Internal Functions
-    ///////////////////////////////
+        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
+            collateralToken,
+            debtToCover
+        );
 
-    function _revertIfHealthFactorIsBroken(address user) internal view {
-        uint256 healthFactor = _getHealthFactor(user);
-        if (healthFactor < MIN_HEALTH_FACTOR) {
-            revert DSCEngine__BreaksHealthFactor(healthFactor);
+        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
+            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
+        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
+            bonusCollateral;
+
+        _redeemCollateral(
+            collateralToken,
+            totalCollateralToRedeem,
+            user,
+            msg.sender
+        );
+        _burnDsc(debtToCover, user, msg.sender);
+
+        uint256 endingUserHealthFactor = _getHealthFactor(user);
+        // This conditional should never hit, but just in case
+        if (endingUserHealthFactor <= startingUserHealthFactor) {
+            revert DSCEngine__HealthFactorNotImproved();
         }
+        _revertIfHealthFactorIsBroken(msg.sender);
     }
 
-    function _getHealthFactor(address user) private view returns (uint256) {
-        (
-            uint256 totalCollateralValue,
-            uint256 totalDscMinted
-        ) = _getAccountInformation(user);
-
-        return
-            ((totalCollateralValue * LIQUIDATION_THRESHOLD * PRECISION) /
-                LIQUIDATION_PRECISION) / totalDscMinted;
+    function redeemCollateralForDsc(
+        address token,
+        uint256 collateralAmount,
+        uint256 dscToBurn
+    ) external {
+        // Call internal implementations directly to avoid external call overhead and reentrancy concerns
+        _burnDsc(dscToBurn, msg.sender, msg.sender);
+        _redeemCollateral(token, collateralAmount, msg.sender, msg.sender);
+        _revertIfHealthFactorIsBroken(msg.sender);
     }
 
-    function _getAccountInformation(
-        address user
-    )
-        private
-        view
-        returns (uint256 totalCollateralValue, uint256 totalDscMinted)
-    {
-        totalDscMinted = s_DSCMinted[user];
-        totalCollateralValue = getAccountCollateralValue(user);
+    /*/////////////////////////////////////////////////////////////
+                         PUBLIC FUNCTIONS
+    /////////////////////////////////////////////////////////////*/
+    function depositCollateral(
+        address token,
+        uint256 amount
+    ) public moreThanZero(amount) isAllowedToken(token) nonReentrant {
+        s_collateralDeposited[msg.sender][token] += amount;
+        emit CollateralDeposited(msg.sender, token, amount);
+
+        bool success = IERC20(token).transferFrom(
+            msg.sender,
+            address(this),
+            amount
+        );
+        if (!success) revert DSCEngine__TransferFailed();
     }
 
-    function revertIfHealthFactorIsBroken(address user) internal view {}
+    function mintDsc(uint256 amount) public moreThanZero(amount) nonReentrant {
+        s_DSCMinted[msg.sender] += amount;
+        _revertIfHealthFactorIsBroken(msg.sender);
 
-    ///////////////////
-    // Public Functions
-    ///////////////////
+        i_dsc.mint(msg.sender, amount);
+        emit DscMinted(msg.sender, amount);
+    }
 
     function getAccountCollateralValue(
         address user
-    ) public view returns (uint256 totalCollateralValueInUsd) {
-        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
-            address token = s_collateralTokens[index];
+    ) public view returns (uint256 totalValue) {
+        for (uint256 i; i < s_collateralTokens.length; i++) {
+            address token = s_collateralTokens[i];
             uint256 amount = s_collateralDeposited[user][token];
-            totalCollateralValueInUsd += getUsdValue(token, amount);
+            totalValue += getUsdValue(token, amount);
         }
-        return totalCollateralValueInUsd;
+    }
+
+    function getTokenAmountFromUsd(
+        address token,
+        uint256 usdAmount
+    ) public view returns (uint256) {
+        address feed = s_priceFeeds[token];
+        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
+        (, int256 price, , , ) = priceFeed.latestRoundData();
+        uint256 tokenPriceInUsd = uint256(price) * ADDITIONAL_FEED_PRECISION;
+        return (usdAmount * PRECISION) / tokenPriceInUsd;
     }
 
     function getUsdValue(
         address token,
         uint256 amount
     ) public view returns (uint256) {
-        AggregatorV3Interface priceFeed = AggregatorV3Interface(
-            s_priceFeeds[token]
+        address feed = s_priceFeeds[token];
+        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
+        (, int256 price, , , ) = priceFeed.latestRoundData();
+        uint256 adjustedPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
+        console.log("adjusted price is ", adjustedPrice);
+        return (amount * adjustedPrice) / PRECISION;
+    }
+
+    /*/////////////////////////////////////////////////////////////
+                             INTERNAL & PRIVATE
+    /////////////////////////////////////////////////////////////*/
+
+    function _redeemCollateral(
+        address tokenCollateralAddress,
+        uint256 amountCollateral,
+        address from,
+        address to
+    ) private {
+        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
+        emit CollateralRedeemed(
+            from,
+            to,
+            tokenCollateralAddress,
+            amountCollateral
+        );
+        bool success = IERC20(tokenCollateralAddress).transfer(
+            to,
+            amountCollateral
         );
+        if (!success) {
+            revert DSCEngine__TransferFailed();
+        }
+    }
 
-        (, int256 price, , , ) = priceFeed.latestRoundData();
+    function _burnDsc(
+        uint256 amountDscToBurn,
+        address onBehalfOf,
+        address dscFrom
+    ) private {
+        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
 
-        // Chainlink price decimals = 8, so we normalize it to 18 decimals
-        // Example: ETH price = $2,500.00 => price = 250000000000 (with 8 decimals)
-        uint256 adjustedPrice = uint256(price) * ADDITIONAL_FEED_PRECISION;
+        bool success = i_dsc.transferFrom(
+            dscFrom,
+            address(this),
+            amountDscToBurn
+        );
+        // This conditional is hypothetically unreachable
+        if (!success) {
+            revert DSCEngine__TransferFailed();
+        }
+        i_dsc.burn(amountDscToBurn);
+    }
 
-        return (amount * adjustedPrice) / PRECISION;
+    function _getAccountInformation(
+        address user
+    ) internal view returns (uint256 collateralValue, uint256 dscMinted) {
+        collateralValue = getAccountCollateralValue(user);
+        dscMinted = s_DSCMinted[user];
     }
+
+    function _getHealthFactor(address user) internal view returns (uint256) {
+        (
+            uint256 totalCollateralValue,
+            uint256 totalDscMinted
+        ) = _getAccountInformation(user);
+        if (totalDscMinted == 0) return type(uint256).max;
+        return
+            ((totalCollateralValue * LIQUIDATION_THRESHOLD * PRECISION) /
+                LIQUIDATION_PRECISION) / totalDscMinted;
+    }
+
+    function _revertIfHealthFactorIsBroken(address user) internal view {
+        uint256 hf = _getHealthFactor(user);
+        if (hf < MIN_HEALTH_FACTOR) revert DSCEngine__BreaksHealthFactor(hf);
+    }
+
+    /*/////////////////////////////////////////////////////////////
+                          VIEW & PURE
+    /////////////////////////////////////////////////////////////*/
+    // All view/pure functions are declared above with correct visibility
 }
