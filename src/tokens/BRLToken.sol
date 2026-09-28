// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title BRLToken
/// @notice Real tokenizado fictício: representa as reservas usadas na perna financeira da liquidação DvP.
/// @dev Apenas para testnet. Duas casas decimais, então 1 unidade = 1 centavo (100 = R$ 1,00).
/// O mint é restrito ao papel MINTER_ROLE (o admin do protocolo, simulando o Banco Central).
contract BRLToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Real Tokenizado (Simulado)", "BRLt") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function decimals() public pure override returns (uint8) {
        return 2;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
