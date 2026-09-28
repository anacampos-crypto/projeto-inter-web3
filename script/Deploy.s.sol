// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {CreditInterbankOffer} from "../src/CreditInterbankOffer.sol";
import {BRLToken} from "../src/tokens/BRLToken.sol";
import {CDIPositionToken} from "../src/tokens/CDIPositionToken.sol";

/// @notice Implanta os três contratos e liga os papéis entre eles.
/// @dev A conta que assina vira admin de tudo. Exemplo local:
///   anvil
///   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key <chave do anvil>
/// Cadastro de instituições, limites e mint de BRL tokenizado ficam a cargo do admin depois do deploy.
contract Deploy is Script {
    function run() external returns (CreditInterbankOffer offerContract, BRLToken brl, CDIPositionToken position) {
        vm.startBroadcast();
        address admin = msg.sender;

        brl = new BRLToken(admin);
        position = new CDIPositionToken(admin);
        offerContract = new CreditInterbankOffer(admin, brl, position);
        position.grantRole(position.MINTER_ROLE(), address(offerContract));

        vm.stopBroadcast();

        console.log("BRLToken:", address(brl));
        console.log("CDIPositionToken:", address(position));
        console.log("CreditInterbankOffer:", address(offerContract));
    }
}
