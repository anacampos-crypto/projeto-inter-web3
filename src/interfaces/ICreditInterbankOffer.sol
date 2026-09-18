// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICreditInterbankOffer
/// @notice Interface do protocolo de crédito interfinanceiro overnight.
/// @dev Entregável da Semana 1. A implementação real entra na Semana 2.
interface ICreditInterbankOffer {
    enum OfferStatus {
        Offered,
        Accepted,
        Settled,
        Cancelled
    }

    struct Offer {
        uint256 id;
        address lender;
        address borrower;
        uint256 amount;
        uint256 rateCDI;
        uint256 term;
        OfferStatus status;
        uint256 createdAt;
        uint256 settledAt;
    }

    event OfferCreated(
        uint256 indexed offerId,
        address indexed lender,
        address indexed borrower,
        uint256 amount,
        uint256 rateCDI,
        uint256 term
    );
    event OfferAccepted(uint256 indexed offerId, address indexed borrower, uint256 timestamp);
    event OfferSettled(uint256 indexed offerId, uint256 timestamp);
    event OfferCancelled(uint256 indexed offerId, uint256 timestamp);

    error InsufficientLimit(address borrower, uint256 requested, uint256 available);
    error OfferNotFound(uint256 offerId);
    error InvalidOfferStatus(uint256 offerId, OfferStatus current, OfferStatus expected);
    error NotOfferOwner(uint256 offerId, address caller);
    error NotEligibleBorrower(uint256 offerId, address caller);
    error InvalidOfferParameters(uint256 amount, uint256 term);

    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term)
        external
        returns (uint256 offerId);
    function acceptOffer(uint256 offerId) external;
    function cancelOffer(uint256 offerId) external;
    function getOffer(uint256 offerId) external view returns (Offer memory);
    function getOfferStatus(uint256 offerId) external view returns (OfferStatus);
    function availableLimit(address institution) external view returns (uint256);
}
