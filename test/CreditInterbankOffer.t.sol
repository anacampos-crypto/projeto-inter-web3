// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {CreditInterbankOffer} from "../src/CreditInterbankOffer.sol";
import {ICreditInterbankOffer} from "../src/interfaces/ICreditInterbankOffer.sol";
import {BRLToken} from "../src/tokens/BRLToken.sol";
import {CDIPositionToken} from "../src/tokens/CDIPositionToken.sol";

contract CreditInterbankOfferTest is Test {
    CreditInterbankOffer internal offerContract;
    BRLToken internal brl;
    CDIPositionToken internal position;

    address internal admin = makeAddr("admin");
    address internal lender = makeAddr("bancoA");
    address internal borrower = makeAddr("bancoB");
    address internal outsider = makeAddr("bancoC");
    address internal stranger = makeAddr("naoCadastrado");

    // Valores em centavos de BRL tokenizado (2 casas decimais).
    uint256 internal constant AMOUNT = 1_000_000_00; // R$ 1.000.000,00
    uint256 internal constant BORROWER_LIMIT = 5_000_000_00; // R$ 5.000.000,00
    uint256 internal constant RATE_100_CDI = 10_000; // 100% do CDI em pontos-base
    uint256 internal constant TERM_OVERNIGHT = 1; // dias
    uint256 internal constant VALIDITY = 1 hours;

    function setUp() public {
        vm.startPrank(admin);
        brl = new BRLToken(admin);
        position = new CDIPositionToken(admin);
        offerContract = new CreditInterbankOffer(admin, brl, position);
        position.grantRole(position.MINTER_ROLE(), address(offerContract));

        offerContract.registerInstitution(lender);
        offerContract.registerInstitution(borrower);
        offerContract.registerInstitution(outsider);
        offerContract.setCreditLimit(borrower, BORROWER_LIMIT);

        brl.mint(lender, 10 * AMOUNT);
        vm.stopPrank();

        vm.prank(lender);
        brl.approve(address(offerContract), type(uint256).max);
    }

    function _createDefaultOffer() internal returns (uint256 offerId) {
        vm.prank(lender);
        offerId = offerContract.createOffer(borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    // ---------------------------------------------------------------------
    // Criação (RF01) e filtro de limite
    // ---------------------------------------------------------------------

    function test_CreateOffer_SetsStatusToOffered() public {
        vm.expectEmit(true, true, true, true, address(offerContract));
        emit ICreditInterbankOffer.OfferCreated(
            1, lender, borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, block.timestamp + VALIDITY
        );
        uint256 offerId = _createDefaultOffer();

        ICreditInterbankOffer.Offer memory offer = offerContract.getOffer(offerId);
        assertEq(offer.id, 1);
        assertEq(offer.lender, lender);
        assertEq(offer.borrower, borrower);
        assertEq(offer.amount, AMOUNT);
        assertEq(offer.rateCDI, RATE_100_CDI);
        assertEq(offer.term, TERM_OVERNIGHT);
        assertEq(uint256(offer.status), uint256(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(offer.createdAt, block.timestamp);
        assertEq(offer.settledAt, 0);
        assertEq(offer.expiresAt, block.timestamp + VALIDITY);
    }

    function test_CreateOffer_RevertsOnZeroAmount() public {
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.InvalidOfferParameters.selector, 0, RATE_100_CDI, TERM_OVERNIGHT
            )
        );
        offerContract.createOffer(borrower, 0, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function test_CreateOffer_RevertsOnZeroRate() public {
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(ICreditInterbankOffer.InvalidOfferParameters.selector, AMOUNT, 0, TERM_OVERNIGHT)
        );
        offerContract.createOffer(borrower, AMOUNT, 0, TERM_OVERNIGHT, VALIDITY);
    }

    function test_CreateOffer_RevertsOnZeroTerm() public {
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(ICreditInterbankOffer.InvalidOfferParameters.selector, AMOUNT, RATE_100_CDI, 0)
        );
        offerContract.createOffer(borrower, AMOUNT, RATE_100_CDI, 0, VALIDITY);
    }

    function test_CreateOffer_RevertsOnZeroValidityWindow() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.InvalidValidityWindow.selector, 0));
        offerContract.createOffer(borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, 0);
    }

    function test_CreateOffer_RevertsWhenLenderIsNotRegistered() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotRegisteredInstitution.selector, stranger));
        offerContract.createOffer(borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function test_CreateOffer_RevertsWhenBorrowerIsNotRegistered() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotRegisteredInstitution.selector, stranger));
        offerContract.createOffer(stranger, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function test_CreateOffer_RevertsWhenBorrowerIsLender() public {
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.InvalidCounterparty.selector, lender, lender));
        offerContract.createOffer(lender, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function test_CreateOffer_RevertsWhenBorrowerLimitIsInsufficient() public {
        // bancoC está cadastrado, mas sem limite definido.
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.InsufficientLimit.selector, outsider, AMOUNT, 0));
        offerContract.createOffer(outsider, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    // ---------------------------------------------------------------------
    // Aceite e liquidação DvP (RF02, RF03) — caminho feliz
    // ---------------------------------------------------------------------

    function test_AcceptOffer_SettlesAtomically() public {
        uint256 offerId = _createDefaultOffer();
        uint256 lenderBalanceBefore = brl.balanceOf(lender);

        vm.expectEmit(true, true, false, true, address(offerContract));
        emit ICreditInterbankOffer.OfferAccepted(offerId, borrower, block.timestamp);
        vm.expectEmit(true, true, true, true, address(offerContract));
        emit ICreditInterbankOffer.OfferSettled(
            offerId, lender, borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, offerId, block.timestamp
        );

        vm.prank(borrower);
        offerContract.acceptOffer(offerId);

        // Perna financeira: BRL tokenizado saiu do ofertante e chegou ao tomador.
        assertEq(brl.balanceOf(lender), lenderBalanceBefore - AMOUNT);
        assertEq(brl.balanceOf(borrower), AMOUNT);
        // Perna do ativo: NFT de posição emitido para o ofertante, com tokenId = offerId.
        assertEq(position.ownerOf(offerId), lender);
        // Limite do tomador consumido.
        assertEq(offerContract.availableLimit(borrower), BORROWER_LIMIT - AMOUNT);
        // Estado final.
        ICreditInterbankOffer.Offer memory offer = offerContract.getOffer(offerId);
        assertEq(uint256(offer.status), uint256(ICreditInterbankOffer.OfferStatus.Settled));
        assertEq(offer.settledAt, block.timestamp);
    }

    function test_AcceptOffer_RevertsWhenCallerIsNotBorrower() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotEligibleBorrower.selector, offerId, outsider));
        offerContract.acceptOffer(offerId);
    }

    function test_AcceptOffer_RevertsWhenLimitWasReducedAfterOffer() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(admin);
        offerContract.setCreditLimit(borrower, AMOUNT - 1);

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(ICreditInterbankOffer.InsufficientLimit.selector, borrower, AMOUNT, AMOUNT - 1)
        );
        offerContract.acceptOffer(offerId);
    }

    function test_AcceptOffer_RevertsEntirelyWhenCashLegFails() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(lender);
        brl.approve(address(offerContract), 0);

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(offerContract), 0, AMOUNT)
        );
        offerContract.acceptOffer(offerId);

        // Nada foi gravado: oferta continua Ofertada, limite intacto, nenhum NFT emitido.
        assertEq(uint256(offerContract.getOfferStatus(offerId)), uint256(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(offerContract.availableLimit(borrower), BORROWER_LIMIT);
        assertEq(position.balanceOf(lender), 0);
    }

    function test_AcceptOffer_RevertsWhenAlreadySettled() public {
        uint256 offerId = _createDefaultOffer();
        vm.startPrank(borrower);
        offerContract.acceptOffer(offerId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.InvalidOfferStatus.selector,
                offerId,
                ICreditInterbankOffer.OfferStatus.Settled,
                ICreditInterbankOffer.OfferStatus.Offered
            )
        );
        offerContract.acceptOffer(offerId);
        vm.stopPrank();
    }

    function test_AcceptOffer_RevertsWhenBorrowerWasRevoked() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(admin);
        offerContract.revokeInstitution(borrower);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotRegisteredInstitution.selector, borrower));
        offerContract.acceptOffer(offerId);
    }

    function test_AcceptOffer_RevertsAfterValidityWindowElapses() public {
        uint256 offerId = _createDefaultOffer();
        uint256 expiresAt = offerContract.getOffer(offerId).expiresAt;
        vm.warp(expiresAt);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferHasExpired.selector, offerId, expiresAt));
        offerContract.acceptOffer(offerId);
    }

    // ---------------------------------------------------------------------
    // Rejeição
    // ---------------------------------------------------------------------

    function test_RejectOffer_SetsStatusToRejected() public {
        uint256 offerId = _createDefaultOffer();

        vm.expectEmit(true, true, false, true, address(offerContract));
        emit ICreditInterbankOffer.OfferRejected(offerId, borrower, block.timestamp);
        vm.prank(borrower);
        offerContract.rejectOffer(offerId);

        assertEq(uint256(offerContract.getOfferStatus(offerId)), uint256(ICreditInterbankOffer.OfferStatus.Rejected));
    }

    function test_RejectOffer_OnlyBorrowerCanReject() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotEligibleBorrower.selector, offerId, lender));
        offerContract.rejectOffer(offerId);
    }

    function test_RejectOffer_RevertsAfterValidityWindowElapses() public {
        uint256 offerId = _createDefaultOffer();
        uint256 expiresAt = offerContract.getOffer(offerId).expiresAt;
        vm.warp(expiresAt);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferHasExpired.selector, offerId, expiresAt));
        offerContract.rejectOffer(offerId);
    }

    function test_AcceptOffer_RevertsWhenOfferWasRejected() public {
        uint256 offerId = _createDefaultOffer();
        vm.startPrank(borrower);
        offerContract.rejectOffer(offerId);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.InvalidOfferStatus.selector,
                offerId,
                ICreditInterbankOffer.OfferStatus.Rejected,
                ICreditInterbankOffer.OfferStatus.Offered
            )
        );
        offerContract.acceptOffer(offerId);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Cancelamento (RF06)
    // ---------------------------------------------------------------------

    function test_CancelOffer_SetsStatusToCancelled() public {
        uint256 offerId = _createDefaultOffer();

        vm.expectEmit(true, false, false, true, address(offerContract));
        emit ICreditInterbankOffer.OfferCancelled(offerId, block.timestamp);
        vm.prank(lender);
        offerContract.cancelOffer(offerId);

        assertEq(uint256(offerContract.getOfferStatus(offerId)), uint256(ICreditInterbankOffer.OfferStatus.Cancelled));
    }

    function test_CancelOffer_OnlyLenderCanCancel() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotOfferOwner.selector, offerId, borrower));
        offerContract.cancelOffer(offerId);
    }

    function test_CancelOffer_RevertsAfterSettlement() public {
        uint256 offerId = _createDefaultOffer();
        vm.prank(borrower);
        offerContract.acceptOffer(offerId);

        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.InvalidOfferStatus.selector,
                offerId,
                ICreditInterbankOffer.OfferStatus.Settled,
                ICreditInterbankOffer.OfferStatus.Offered
            )
        );
        offerContract.cancelOffer(offerId);
    }

    function test_CancelOffer_RevertsAfterValidityWindowElapses() public {
        uint256 offerId = _createDefaultOffer();
        uint256 expiresAt = offerContract.getOffer(offerId).expiresAt;
        vm.warp(expiresAt);

        vm.prank(lender);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferHasExpired.selector, offerId, expiresAt));
        offerContract.cancelOffer(offerId);
    }

    // ---------------------------------------------------------------------
    // Expiração
    // ---------------------------------------------------------------------

    function test_GetOfferStatus_ReturnsExpired_AfterValidityWindowElapses() public {
        uint256 offerId = _createDefaultOffer();
        vm.warp(offerContract.getOffer(offerId).expiresAt);

        assertEq(uint256(offerContract.getOfferStatus(offerId)), uint256(ICreditInterbankOffer.OfferStatus.Expired));
        // getOffer continua com o último status gravado até alguém chamar expireOffer.
        assertEq(uint256(offerContract.getOffer(offerId).status), uint256(ICreditInterbankOffer.OfferStatus.Offered));
    }

    function test_ExpireOffer_PersistsExpiredStatusAndEmitsEvent() public {
        uint256 offerId = _createDefaultOffer();
        vm.warp(offerContract.getOffer(offerId).expiresAt);

        vm.expectEmit(true, false, false, true, address(offerContract));
        emit ICreditInterbankOffer.OfferExpired(offerId, block.timestamp);
        vm.prank(stranger); // qualquer conta pode chamar
        offerContract.expireOffer(offerId);

        assertEq(uint256(offerContract.getOffer(offerId).status), uint256(ICreditInterbankOffer.OfferStatus.Expired));
    }

    function test_ExpireOffer_RevertsBeforeValidityWindowElapses() public {
        uint256 offerId = _createDefaultOffer();
        uint256 expiresAt = offerContract.getOffer(offerId).expiresAt;
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferNotYetExpired.selector, offerId, expiresAt));
        offerContract.expireOffer(offerId);
    }

    // ---------------------------------------------------------------------
    // Administração, cadastro e tokens
    // ---------------------------------------------------------------------

    function test_RegisterInstitution_OnlyAdmin() public {
        bytes32 adminRole = offerContract.DEFAULT_ADMIN_ROLE();
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, lender, adminRole)
        );
        offerContract.registerInstitution(stranger);
    }

    function test_RegisterInstitution_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(offerContract));
        emit ICreditInterbankOffer.InstitutionRegistered(stranger, block.timestamp);
        vm.prank(admin);
        offerContract.registerInstitution(stranger);
        assertTrue(offerContract.isRegisteredInstitution(stranger));
    }

    function test_SetCreditLimit_EmitsEventWithPreviousValue() public {
        vm.expectEmit(true, false, false, true, address(offerContract));
        emit ICreditInterbankOffer.CreditLimitUpdated(borrower, BORROWER_LIMIT, AMOUNT, block.timestamp);
        vm.prank(admin);
        offerContract.setCreditLimit(borrower, AMOUNT);
        assertEq(offerContract.availableLimit(borrower), AMOUNT);
    }

    function test_SetCreditLimit_RevertsForUnregisteredInstitution() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotRegisteredInstitution.selector, stranger));
        offerContract.setCreditLimit(stranger, AMOUNT);
    }

    function test_GetOffer_RevertsWhenOfferDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.OfferNotFound.selector, 42));
        offerContract.getOffer(42);
    }

    function test_PositionToken_OnlyOfferContractCanMint() public {
        bytes32 minterRole = position.MINTER_ROLE();
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, lender, minterRole)
        );
        position.mint(lender, 1);
    }

    function test_BRLToken_HasTwoDecimals() public view {
        assertEq(brl.decimals(), 2);
    }
}
