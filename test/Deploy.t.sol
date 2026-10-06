// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Deploy} from "../script/Deploy.s.sol";

contract DeployTest is Test {
    Deploy internal script;
    address internal deployer = makeAddr("deployer");

    function setUp() public {
        script = new Deploy();
    }

    function _localConfig() internal view returns (Deploy.Config memory) {
        return script.loadConfig(string.concat(vm.projectRoot(), "/script/config/local.json"));
    }

    function test_LoadConfig_ReadsLocalFile() public view {
        Deploy.Config memory cfg = _localConfig();
        assertEq(cfg.chainId, 31337);
        assertEq(cfg.admin, address(0));
        assertEq(cfg.institutions.length, 3);
        assertEq(cfg.institutions[0].wallet, 0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
        assertEq(cfg.institutions[0].creditLimit, 500000000);
        assertEq(cfg.institutions[0].brlMint, 1000000000);
        // As carteiras precisam ser as contas 1, 2 e 3 do Anvil, senão o deploy local
        // cadastra endereços sem chave conhecida.
        assertEq(cfg.institutions[1].wallet, 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC);
        assertEq(cfg.institutions[2].wallet, 0x90F79bf6EB2c4f870365E785982E1f101E93b906);
    }

    function test_LoadConfig_AcceptsEmptyInstitutionList() public view {
        // Usa um arquivo de teste: o sepolia.json real recebe as carteiras das instituições.
        Deploy.Config memory cfg =
            script.loadConfig(string.concat(vm.projectRoot(), "/test/fixtures/empty-institutions.json"));
        assertEq(cfg.chainId, 11155111);
        assertEq(cfg.institutions.length, 0);
    }

    function test_Deploy_WiresContractsAndSetsUpInstitutions() public {
        Deploy.Config memory cfg = _localConfig();
        Deploy.Deployment memory d = script.deploy(cfg, deployer);

        assertEq(address(d.offerContract.settlementToken()), address(d.brl));
        assertEq(address(d.offerContract.positionToken()), address(d.position));
        assertTrue(d.position.hasRole(d.position.MINTER_ROLE(), address(d.offerContract)));
        assertTrue(d.offerContract.hasRole(d.offerContract.DEFAULT_ADMIN_ROLE(), deployer));

        for (uint256 i; i < cfg.institutions.length; ++i) {
            Deploy.Institution memory inst = cfg.institutions[i];
            assertTrue(d.offerContract.isRegisteredInstitution(inst.wallet));
            assertEq(d.offerContract.availableLimit(inst.wallet), inst.creditLimit);
            assertEq(d.brl.balanceOf(inst.wallet), inst.brlMint);
        }
    }

    function test_Deploy_HandsOverAdminRoles() public {
        Deploy.Config memory cfg = _localConfig();
        address finalAdmin = makeAddr("finalAdmin");
        cfg.admin = finalAdmin;
        Deploy.Deployment memory d = script.deploy(cfg, deployer);

        bytes32 adminRole = d.offerContract.DEFAULT_ADMIN_ROLE();
        assertTrue(d.offerContract.hasRole(adminRole, finalAdmin));
        assertTrue(d.brl.hasRole(adminRole, finalAdmin));
        assertTrue(d.brl.hasRole(d.brl.MINTER_ROLE(), finalAdmin));
        assertTrue(d.position.hasRole(adminRole, finalAdmin));

        assertFalse(d.offerContract.hasRole(adminRole, deployer));
        assertFalse(d.brl.hasRole(adminRole, deployer));
        assertFalse(d.brl.hasRole(d.brl.MINTER_ROLE(), deployer));
        assertFalse(d.position.hasRole(adminRole, deployer));
    }

    function test_Deploy_RevertsOnChainIdMismatch() public {
        Deploy.Config memory cfg = _localConfig();
        cfg.chainId = 11155111;
        vm.expectRevert("Deploy: chainId do RPC difere do arquivo de configuracao");
        script.deploy(cfg, deployer);
    }
}
