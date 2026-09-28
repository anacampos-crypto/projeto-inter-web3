// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICreditInterbankOffer} from "./interfaces/ICreditInterbankOffer.sol";
import {CDIPositionToken} from "./tokens/CDIPositionToken.sol";

/// @title CreditInterbankOffer
/// @notice Protocolo de crédito interfinanceiro overnight com liquidação DvP.
/// @dev Fluxo: o ofertante cria uma oferta direcionada a um tomador cadastrado; o tomador aceita
/// (ou rejeita). No aceite, na mesma transação, o BRL tokenizado sai do ofertante para o tomador e
/// o NFT de posição é emitido para o ofertante. Se qualquer perna falhar, tudo reverte.
/// Pré-requisito do aceite: o ofertante deu `approve` deste contrato no BRL tokenizado.
contract CreditInterbankOffer is ICreditInterbankOffer, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Papel das carteiras autorizadas a operar (uma por instituição).
    bytes32 public constant INSTITUTION_ROLE = keccak256("INSTITUTION_ROLE");

    IERC20 public immutable settlementToken;
    CDIPositionToken public immutable positionToken;

    uint256 private _nextOfferId;
    mapping(uint256 => Offer) private _offers;
    mapping(address => uint256) private _creditLimit;

    constructor(address admin, IERC20 settlementToken_, CDIPositionToken positionToken_) {
        if (admin == address(0) || address(settlementToken_) == address(0) || address(positionToken_) == address(0)) {
            revert ZeroAddress();
        }
        settlementToken = settlementToken_;
        positionToken = positionToken_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ---------------------------------------------------------------------
    // Administração
    // ---------------------------------------------------------------------

    function registerInstitution(address wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (wallet == address(0)) revert ZeroAddress();
        if (_grantRole(INSTITUTION_ROLE, wallet)) {
            emit InstitutionRegistered(wallet, block.timestamp);
        }
    }

    function revokeInstitution(address wallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_revokeRole(INSTITUTION_ROLE, wallet)) {
            emit InstitutionRevoked(wallet, block.timestamp);
        }
    }

    function setCreditLimit(address institution, uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!hasRole(INSTITUTION_ROLE, institution)) revert NotRegisteredInstitution(institution);
        uint256 previous = _creditLimit[institution];
        _creditLimit[institution] = newLimit;
        emit CreditLimitUpdated(institution, previous, newLimit, block.timestamp);
    }

    // ---------------------------------------------------------------------
    // Ciclo de vida da oferta
    // ---------------------------------------------------------------------

    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term, uint256 validityWindow)
        external
        returns (uint256 offerId)
    {
        _requireInstitution(msg.sender);
        if (borrower == address(0) || borrower == msg.sender) revert InvalidCounterparty(msg.sender, borrower);
        _requireInstitution(borrower);
        if (amount == 0 || rateCDI == 0 || term == 0) revert InvalidOfferParameters(amount, rateCDI, term);
        if (validityWindow == 0) revert InvalidValidityWindow(validityWindow);
        // Filtro de limite: só é possível ofertar para quem tem limite condizente com o valor.
        _requireLimit(borrower, amount);

        offerId = ++_nextOfferId;
        uint256 expiresAt = block.timestamp + validityWindow;
        _offers[offerId] = Offer({
            id: offerId,
            lender: msg.sender,
            borrower: borrower,
            amount: amount,
            rateCDI: rateCDI,
            term: term,
            status: OfferStatus.Offered,
            createdAt: block.timestamp,
            settledAt: 0,
            expiresAt: expiresAt
        });

        emit OfferCreated(offerId, msg.sender, borrower, amount, rateCDI, term, expiresAt);
    }

    function acceptOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = _openOffer(offerId);
        if (msg.sender != offer.borrower) revert NotEligibleBorrower(offerId, msg.sender);
        _requireInstitution(offer.borrower);
        _requireInstitution(offer.lender);
        _requireLimit(offer.borrower, offer.amount);

        // Efeitos antes das interações (checks-effects-interactions).
        _creditLimit[offer.borrower] -= offer.amount;
        offer.status = OfferStatus.Settled;
        offer.settledAt = block.timestamp;
        emit OfferAccepted(offerId, offer.borrower, block.timestamp);

        // DvP: perna financeira e perna do ativo na mesma transação.
        settlementToken.safeTransferFrom(offer.lender, offer.borrower, offer.amount);
        positionToken.mint(offer.lender, offerId);

        emit OfferSettled(
            offerId, offer.lender, offer.borrower, offer.amount, offer.rateCDI, offer.term, offerId, block.timestamp
        );
    }

    function rejectOffer(uint256 offerId) external {
        Offer storage offer = _openOffer(offerId);
        if (msg.sender != offer.borrower) revert NotEligibleBorrower(offerId, msg.sender);
        offer.status = OfferStatus.Rejected;
        emit OfferRejected(offerId, msg.sender, block.timestamp);
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage offer = _openOffer(offerId);
        if (msg.sender != offer.lender) revert NotOfferOwner(offerId, msg.sender);
        offer.status = OfferStatus.Cancelled;
        emit OfferCancelled(offerId, block.timestamp);
    }

    function expireOffer(uint256 offerId) external {
        Offer storage offer = _existingOffer(offerId);
        if (offer.status != OfferStatus.Offered) {
            revert InvalidOfferStatus(offerId, offer.status, OfferStatus.Offered);
        }
        if (block.timestamp < offer.expiresAt) revert OfferNotYetExpired(offerId, offer.expiresAt);
        offer.status = OfferStatus.Expired;
        emit OfferExpired(offerId, block.timestamp);
    }

    // ---------------------------------------------------------------------
    // Leitura
    // ---------------------------------------------------------------------

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return _existingOffer(offerId);
    }

    function getOfferStatus(uint256 offerId) external view returns (OfferStatus) {
        Offer storage offer = _existingOffer(offerId);
        if (offer.status == OfferStatus.Offered && block.timestamp >= offer.expiresAt) {
            return OfferStatus.Expired;
        }
        return offer.status;
    }

    function availableLimit(address institution) external view returns (uint256) {
        return _creditLimit[institution];
    }

    function isRegisteredInstitution(address account) external view returns (bool) {
        return hasRole(INSTITUTION_ROLE, account);
    }

    // ---------------------------------------------------------------------
    // Internas
    // ---------------------------------------------------------------------

    function _existingOffer(uint256 offerId) private view returns (Offer storage offer) {
        offer = _offers[offerId];
        if (offer.id == 0) revert OfferNotFound(offerId);
    }

    /// @dev Oferta que ainda pode ser aceita, rejeitada ou cancelada: existe, está Ofertada e não venceu.
    function _openOffer(uint256 offerId) private view returns (Offer storage offer) {
        offer = _existingOffer(offerId);
        if (offer.status != OfferStatus.Offered) {
            revert InvalidOfferStatus(offerId, offer.status, OfferStatus.Offered);
        }
        if (block.timestamp >= offer.expiresAt) revert OfferHasExpired(offerId, offer.expiresAt);
    }

    function _requireInstitution(address account) private view {
        if (!hasRole(INSTITUTION_ROLE, account)) revert NotRegisteredInstitution(account);
    }

    function _requireLimit(address borrower, uint256 amount) private view {
        uint256 available = _creditLimit[borrower];
        if (available < amount) revert InsufficientLimit(borrower, amount, available);
    }
}
