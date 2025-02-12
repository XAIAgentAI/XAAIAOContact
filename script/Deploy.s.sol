// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from "forge-std/Script.sol";
import {IAO} from "../src/IAO.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {console} from "forge-std/Test.sol";

contract Deploy is Script {
    function run() external returns (address proxy, address logic) {
        string memory privateKeyString = vm.envString("PRIVATE_KEY");
        uint256 deployerPrivateKey;

        if (
            bytes(privateKeyString).length > 0 &&
            bytes(privateKeyString)[0] == "0" &&
            bytes(privateKeyString)[1] == "x"
        ) {
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        } else {
            deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        }

        vm.startBroadcast(deployerPrivateKey);

        (proxy, logic) = deploy();
        vm.stopBroadcast();
        console.log("Proxy Contract deployed at:", proxy);
        console.log("Logic Contract deployed at:", logic);
        return (proxy, logic);
    }

    function deploy() public returns (address proxy, address logic) {
        //        Options memory opts;

        address rewardTokenContract = vm.envAddress("REWARD_TOKEN_CONTRACT");
        console.log("rewardTokenContract Address:", rewardTokenContract);

        proxy = Upgrades.deployUUPSProxy(
            "IAO.sol:IAO",
            abi.encodeCall(IAO.initialize, (msg.sender, rewardTokenContract))
        );
        return (proxy, logic);
    }
}
