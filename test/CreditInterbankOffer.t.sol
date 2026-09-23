// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ICreditInterbankOffer} from "../src/interfaces/ICreditInterbankOffer.sol";

/// @notice Mock temporário da Semana 1; será substituído pelo contrato DvP na Semana 2.
contract CreditInterbankOfferMock is ICreditInterbankOffer {
    uint256 private nextId;
    mapping(uint256 => Offer) private offers;

    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term, uint256 validityWindow)
        external
        returns (uint256 offerId)
    {
        if (amount == 0 || term == 0) revert InvalidOfferParameters(amount, term);
        if (validityWindow == 0) revert InvalidValidityWindow(validityWindow);
        offerId = ++nextId;
        uint256 expiresAt = block.timestamp + validityWindow;
        offers[offerId] = Offer({
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

    function acceptOffer(uint256 offerId) external view {
        Offer storage offer = offers[offerId];
        if (offer.id == 0) revert OfferNotFound(offerId);
        if (offer.status != OfferStatus.Offered) {
            revert InvalidOfferStatus(offerId, offer.status, OfferStatus.Offered);
        }
        if (block.timestamp >= offer.expiresAt) revert OfferHasExpired(offerId, offer.expiresAt);
        revert("not implemented yet - sprint 2");
    }

    function cancelOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        if (offer.id == 0) revert OfferNotFound(offerId);
        if (offer.status != OfferStatus.Offered) {
            revert InvalidOfferStatus(offerId, offer.status, OfferStatus.Offered);
        }
        if (block.timestamp >= offer.expiresAt) revert OfferHasExpired(offerId, offer.expiresAt);
        if (offer.lender != msg.sender) revert NotOfferOwner(offerId, msg.sender);
        offer.status = OfferStatus.Cancelled;
        emit OfferCancelled(offerId, block.timestamp);
    }

    function expireOffer(uint256 offerId) external {
        Offer storage offer = offers[offerId];
        if (offer.id == 0) revert OfferNotFound(offerId);
        if (offer.status != OfferStatus.Offered) {
            revert InvalidOfferStatus(offerId, offer.status, OfferStatus.Offered);
        }
        if (block.timestamp < offer.expiresAt) revert OfferNotYetExpired(offerId, offer.expiresAt);
        offer.status = OfferStatus.Expired;
        emit OfferExpired(offerId, block.timestamp);
    }

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function getOfferStatus(uint256 offerId) external view returns (OfferStatus) {
        Offer storage offer = offers[offerId];
        if (offer.status == OfferStatus.Offered && block.timestamp >= offer.expiresAt) {
            return OfferStatus.Expired;
        }
        return offer.status;
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
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);

        ICreditInterbankOffer.Offer memory offer = offerContract.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(offer.lender, lender);
        assertEq(offer.amount, 100 ether);
        assertEq(offer.expiresAt, block.timestamp + 1 hours);
    }

    function test_CreateOffer_RevertsOnZeroAmount() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.InvalidOfferParameters.selector, 0, 1 days));
        offerContract.createOffer(borrower, 0, 1050, 1 days, 1 hours);
    }

    function test_CreateOffer_RevertsOnZeroValidityWindow() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.InvalidValidityWindow.selector, 0));
        offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 0);
    }

    function test_CancelOffer_OnlyLenderCanCancel() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotOfferOwner.selector, offerId, borrower));
        offerContract.cancelOffer(offerId);
    }

    function test_GetOfferStatus_ReturnsExpired_AfterValidityWindowElapses() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);

        vm.warp(block.timestamp + 1 hours);

        assertEq(uint8(offerContract.getOfferStatus(offerId)), uint8(ICreditInterbankOffer.OfferStatus.Expired));
    }

    function test_ExpireOffer_PersistsExpiredStatusAndEmitsEvent() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);

        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, false, false, true);
        emit ICreditInterbankOffer.OfferExpired(offerId, block.timestamp);
        offerContract.expireOffer(offerId);

        ICreditInterbankOffer.Offer memory offer = offerContract.getOffer(offerId);
        assertEq(uint8(offer.status), uint8(ICreditInterbankOffer.OfferStatus.Expired));
    }

    function test_ExpireOffer_RevertsBeforeValidityWindowElapses() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.OfferNotYetExpired.selector, offerId, block.timestamp + 1 hours
            )
        );
        offerContract.expireOffer(offerId);
    }

    function test_CancelOffer_RevertsAfterValidityWindowElapses() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);
        uint256 expiresAt = block.timestamp + 1 hours;

        vm.warp(expiresAt);

        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferHasExpired.selector, offerId, expiresAt));
        offerContract.cancelOffer(offerId);
    }

    function test_AcceptOffer_RevertsAfterValidityWindowElapses() public {
        vm.prank(lender);
        uint256 offerId = offerContract.createOffer(borrower, 100 ether, 1050, 1 days, 1 hours);
        uint256 expiresAt = block.timestamp + 1 hours;

        vm.warp(expiresAt);

        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferHasExpired.selector, offerId, expiresAt));
        offerContract.acceptOffer(offerId);
    }
}
