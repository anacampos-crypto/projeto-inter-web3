// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title CDIPositionToken
/// @notice NFT que representa uma operação de crédito interfinanceiro liquidada: o direito do
/// ofertante (credor) de receber o valor emprestado do tomador.
/// @dev Não fungível porque cada operação é única (partes, valor, taxa, prazo). O `tokenId` é igual
/// ao `offerId` da oferta que o originou. Só o contrato de ofertas (MINTER_ROLE) emite e queima.
/// `burn` fica disponível para a futura liquidação D+1, que está fora do escopo atual.
contract CDIPositionToken is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC721("Posicao CDI Interbancario", "CDIP") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
