// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/*
    Invariants being tested:
    1. The protocol must always remain overcollateralized.
    2. Users shouldn't be able to mint stablecoins with a bad health factor.
    3. Users should only be liquidatable if their health factor drops below the threshold.
*/

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";
import {console} from "forge-std/console.sol";

contract ContinueOnRevertInvariants is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    Handler public handler;

    // Constants
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() external {
        // Deploy protocol contracts
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();

        // Load mock token and price feed addresses from config
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = helperConfig
            .activeNetworkConfig();

        // Set up fuzzing handler and target it for invariant testing
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    /// @notice Invariant: The protocol should always remain overcollateralized
    /// @dev    WETH and WBTC value in the engine should always be >= DSC total supply
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_protocolMustHaveMoreValueThanTotalSupplyDollars()
        public
        view
    {
        uint256 totalSupply = dsc.totalSupply();

        // Get total deposited WETH & WBTC in engine
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        // Get current USD value of both collaterals
        uint256 wethValue = dsce.getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcDeposited);

        // Debug logs (optional during development)
        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("totalSupply: %s", totalSupply);

        // Invariant: protocol must remain solvent
        assert(wethValue + wbtcValue >= totalSupply);
    }

    /// @notice Helper for debugging handler behavior after fuzz runs
    /// forge-config: default.invariant.fail-on-revert = false
    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
