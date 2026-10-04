// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";

import {CreditInterbankOffer} from "../src/CreditInterbankOffer.sol";
import {BRLToken} from "../src/tokens/BRLToken.sol";
import {CDIPositionToken} from "../src/tokens/CDIPositionToken.sol";

/// @notice Implanta o protocolo e prepara o ambiente a partir de `script/config/<DEPLOY_ENV>.json`.
/// @dev Uso (detalhes no README):
///   DEPLOY_ENV=local   forge script script/Deploy.s.sol --rpc-url local   --broadcast --private-key <chave>
///   DEPLOY_ENV=sepolia forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --account <keystore> --verify
/// Formato do arquivo de configuração:
///   chainId        rede esperada; o script aborta se o RPC apontar para outra.
///   admin          (opcional) admin final. Se omitido, a conta que assina permanece admin.
///   institutions   lista de { wallet, creditLimit, brlMint } com valores em centavos de BRLt.
/// O resultado (endereços, rede, bloco) é gravado em `deployments/<DEPLOY_ENV>.json`.
contract Deploy is Script {
    struct Institution {
        address wallet;
        uint256 creditLimit;
        uint256 brlMint;
    }

    struct Config {
        uint256 chainId;
        address admin;
        Institution[] institutions;
    }

    struct Deployment {
        CreditInterbankOffer offerContract;
        BRLToken brl;
        CDIPositionToken position;
    }

    function run() external returns (Deployment memory d) {
        string memory env = vm.envOr("DEPLOY_ENV", string("local"));
        address deployer = msg.sender;
        require(deployer != DEFAULT_SENDER, "Deploy: informe a conta com --private-key, --account ou --sender");

        Config memory cfg = loadConfig(string.concat(vm.projectRoot(), "/script/config/", env, ".json"));
        d = deploy(cfg, deployer);
        _writeDeployment(env, cfg, deployer, d);
    }

    function loadConfig(string memory path) public view returns (Config memory cfg) {
        string memory json = vm.readFile(path);
        cfg.chainId = vm.parseJsonUint(json, ".chainId");
        if (vm.keyExistsJson(json, ".admin")) cfg.admin = vm.parseJsonAddress(json, ".admin");

        uint256 count;
        while (vm.keyExistsJson(json, string.concat(".institutions[", vm.toString(count), "]"))) {
            ++count;
        }
        cfg.institutions = new Institution[](count);
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".institutions[", vm.toString(i), "]");
            cfg.institutions[i] = Institution({
                wallet: vm.parseJsonAddress(json, string.concat(key, ".wallet")),
                creditLimit: vm.parseJsonUint(json, string.concat(key, ".creditLimit")),
                brlMint: vm.parseJsonUint(json, string.concat(key, ".brlMint"))
            });
        }
    }

    function deploy(Config memory cfg, address deployer) public returns (Deployment memory d) {
        require(block.chainid == cfg.chainId, "Deploy: chainId do RPC difere do arquivo de configuracao");
        address finalAdmin = cfg.admin == address(0) ? deployer : cfg.admin;

        vm.startBroadcast(deployer);

        // O deployer é admin provisório para conseguir configurar tudo na mesma execução.
        d.brl = new BRLToken(deployer);
        d.position = new CDIPositionToken(deployer);
        d.offerContract = new CreditInterbankOffer(deployer, d.brl, d.position);
        d.position.grantRole(d.position.MINTER_ROLE(), address(d.offerContract));

        for (uint256 i; i < cfg.institutions.length; ++i) {
            Institution memory inst = cfg.institutions[i];
            d.offerContract.registerInstitution(inst.wallet);
            if (inst.creditLimit > 0) d.offerContract.setCreditLimit(inst.wallet, inst.creditLimit);
            if (inst.brlMint > 0) d.brl.mint(inst.wallet, inst.brlMint);
        }

        if (finalAdmin != deployer) _handOverAdmin(d, deployer, finalAdmin);

        vm.stopBroadcast();

        console.log("BRLToken:", address(d.brl));
        console.log("CDIPositionToken:", address(d.position));
        console.log("CreditInterbankOffer:", address(d.offerContract));
        console.log("Admin:", finalAdmin);
    }

    /// @dev Concede os papéis administrativos ao admin final e remove os do deployer.
    function _handOverAdmin(Deployment memory d, address deployer, address finalAdmin) private {
        bytes32 adminRole = d.offerContract.DEFAULT_ADMIN_ROLE();

        d.brl.grantRole(d.brl.MINTER_ROLE(), finalAdmin);
        d.brl.grantRole(adminRole, finalAdmin);
        d.position.grantRole(adminRole, finalAdmin);
        d.offerContract.grantRole(adminRole, finalAdmin);

        d.brl.renounceRole(d.brl.MINTER_ROLE(), deployer);
        d.brl.renounceRole(adminRole, deployer);
        d.position.renounceRole(adminRole, deployer);
        d.offerContract.renounceRole(adminRole, deployer);
    }

    function _writeDeployment(string memory env, Config memory cfg, address deployer, Deployment memory d) private {
        string memory obj = "deployment";
        vm.serializeString(obj, "environment", env);
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeUint(obj, "startBlock", block.number);
        vm.serializeAddress(obj, "deployer", deployer);
        vm.serializeAddress(obj, "admin", cfg.admin == address(0) ? deployer : cfg.admin);
        vm.serializeAddress(obj, "BRLToken", address(d.brl));
        vm.serializeAddress(obj, "CDIPositionToken", address(d.position));
        string memory json = vm.serializeAddress(obj, "CreditInterbankOffer", address(d.offerContract));

        string memory dir = string.concat(vm.projectRoot(), "/deployments");
        vm.createDir(dir, true);
        vm.writeJson(json, string.concat(dir, "/", env, ".json"));
    }
}
