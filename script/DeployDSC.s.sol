// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

// Imports
import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.sol";

/**
 * @title DeployDSC
 * @notice Script for deploying the Decentralized StableCoin system
 * @dev This script handles the deployment of both the DSC token and DSCEngine contracts
 */
contract DeployDSC is Script {
    /**
     * @notice Main deployment function
     * @return dsc The deployed DecentralizedStableCoin contract
     * @return dscEngine The deployed DSCEngine contract
     * @return helperConfig The helper configuration contract
     */
    function run()
        external
        returns (
            DecentralizedStableCoin dsc,
            DSCEngine dscEngine,
            HelperConfig helperConfig
        )
    {
        // Initialize configuration
        helperConfig = new HelperConfig();

        // Get network-specific configuration
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        // Prepare token and price feed arrays
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = weth;
        tokenAddresses[1] = wbtc;

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed;
        priceFeedAddresses[1] = wbtcUsdPriceFeed;

        // Start broadcast and deploy contracts
        vm.startBroadcast(deployerKey);

        // Deploy DSC token
        dsc = new DecentralizedStableCoin();

        // Deploy DSC Engine with configuration
        dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );

        // Transfer ownership of DSC to the engine
        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();
    }
}
