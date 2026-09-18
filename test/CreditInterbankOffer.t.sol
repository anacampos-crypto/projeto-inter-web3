// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ICreditInterbankOffer} from "../src/interfaces/ICreditInterbankOffer.sol";

/// @notice Mock temporário da Semana 1; será substituído pelo contrato DvP na Semana 2.
contract CreditInterbankOfferMock is ICreditInterbankOffer {
    uint256 private nextId;
    mapping(uint256 => Offer) private offers;

    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term)
        external
        returns (uint256 offerId)
    {
        if (amount == 0 || term == 0) revert InvalidOfferParameters(amount, term);
        offerId = ++nextId;
        offers[offerId] = Offer({
            id: offerId,
            lender: msg.sender,
            borrower: borrower,
            amount: amount,
            rateCDI: rateCDI,
            term: term,
            status: OfferStatus.Offered,
            createdAt: block.timestamp,
            settledAt: 0
        });
        emit OfferCreated(offerId, msg.sender, borrower, amount, rateCDI, term);
    }

    function acceptOffer(uint256) external pure {
        revert("not implemented yet - sprint 2");
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        if (offer.id == 0) revert OfferNotFound(offerId);
        if (offer.status != OfferStatus.Offered) {
            revert InvalidOfferStatus(offerId, offer.status, OfferStatus.Offered);
        }
        if (offer.lender != msg.sender) revert NotOfferOwner(offerId, msg.sender);
        offer.status = OfferStatus.Cancelled;
        emit OfferCancelled(offerId, block.timestamp);
    }

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function getOfferStatus(uint256 offerId) external view returns (OfferStatus) {
        return offers[offerId].status;
    }

    function availableLimit(address) external pure returns (uint256) {
        return 1_000_000e18;
    }
}

contract CreditInterbankOfferTest is Test {
    CreditInterbankOfferMock internal offerContract;
    address internal lender = makeAddr("lender");
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        offerContract = new CreditInterbankOfferMock();
    }

    function test_CreateOffer_SetsStatusToOffered() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days);

        ICreditInterbankOffer.Offer memory offer = offerContract.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(offer.lender, lender);
        assertEq(offer.amount, 100 ether);
    }

    function test_CreateOffer_RevertsOnZeroAmount() public {
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(ICreditInterbankOffer.InvalidOfferParameters.selector, 0, 1 days)
        );
        offerContract.createOffer(borrower, 0, 1050, 1 days);
    }

    function test_CancelOffer_OnlyLenderCanCancel() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days);

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(ICreditInterbankOffer.NotOfferOwner.selector, offerId, borrower)
        );
        offerContract.cancelOffer(offerId);
    }
}
