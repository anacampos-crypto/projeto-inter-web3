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
        Cancelled,
        Expired
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
        uint256 expiresAt;
    }

    event OfferCreated(
        uint256 indexed offerId,
        address indexed lender,
        address indexed borrower,
        uint256 amount,
        uint256 rateCDI,
        uint256 term,
        uint256 expiresAt
    );
    event OfferAccepted(uint256 indexed offerId, address indexed borrower, uint256 timestamp);
    event OfferSettled(uint256 indexed offerId, uint256 timestamp);
    event OfferCancelled(uint256 indexed offerId, uint256 timestamp);
    event OfferExpired(uint256 indexed offerId, uint256 timestamp);

    error InsufficientLimit(address borrower, uint256 requested, uint256 available);
    error OfferNotFound(uint256 offerId);
    error InvalidOfferStatus(uint256 offerId, OfferStatus current, OfferStatus expected);
    error NotOfferOwner(uint256 offerId, address caller);
    error NotEligibleBorrower(uint256 offerId, address caller);
    error InvalidOfferParameters(uint256 amount, uint256 term);
    error InvalidValidityWindow(uint256 validityWindow);
    error OfferHasExpired(uint256 offerId, uint256 expiresAt);
    error OfferNotYetExpired(uint256 offerId, uint256 expiresAt);

    /// @param validityWindow duration in seconds during which the offer can still be accepted or
    /// cancelled, counted from the block timestamp of creation; independent from `term`, which is
    /// the tenor of the overnight loan itself.
    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term, uint256 validityWindow)
        external
        returns (uint256 offerId);
    function acceptOffer(uint256 offerId) external;
    function cancelOffer(uint256 offerId) external;
    /// @notice Permissionless transition that persists `Offered -> Expired` once
    /// `block.timestamp >= expiresAt`. Reverts if called before expiry or from any other status.
    function expireOffer(uint256 offerId) external;
    function getOffer(uint256 offerId) external view returns (Offer memory);
    /// @notice Returns `Expired` once the validity window has elapsed, even if `expireOffer` has
    /// not been called yet to persist the transition on-chain.
    function getOfferStatus(uint256 offerId) external view returns (OfferStatus);
    function availableLimit(address institution) external view returns (uint256);
}
