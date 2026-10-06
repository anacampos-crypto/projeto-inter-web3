// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors, IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {CreditInterbankOffer} from "../src/CreditInterbankOffer.sol";
import {ICreditInterbankOffer} from "../src/interfaces/ICreditInterbankOffer.sol";
import {BRLToken} from "../src/tokens/BRLToken.sol";
import {CDIPositionToken} from "../src/tokens/CDIPositionToken.sol";

/// @notice Ofertante malicioso: ao receber o NFT de posição durante a liquidação, tenta
/// reentrar no contrato de ofertas. Serve para provar que a reentrância é bloqueada.
contract ReentrantLender is IERC721Receiver {
    enum Attack {
        None,
        AcceptOther,
        CancelSame
    }

    CreditInterbankOffer internal immutable offers;
    Attack public attack;
    uint256 public targetOfferId;

    constructor(CreditInterbankOffer offers_, BRLToken brl) {
        offers = offers_;
        brl.approve(address(offers_), type(uint256).max);
    }

    function setAttack(Attack attack_, uint256 targetOfferId_) external {
        attack = attack_;
        targetOfferId = targetOfferId_;
    }

    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term, uint256 validity)
        external
        returns (uint256)
    {
        return offers.createOffer(borrower, amount, rateCDI, term, validity);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (attack == Attack.AcceptOther) offers.acceptOffer(targetOfferId);
        if (attack == Attack.CancelSame) offers.cancelOffer(targetOfferId);
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @notice Ofertante que é um contrato sem `onERC721Received`: não consegue receber o NFT.
contract NonReceiverLender {
    CreditInterbankOffer internal immutable offers;

    constructor(CreditInterbankOffer offers_, BRLToken brl) {
        offers = offers_;
        brl.approve(address(offers_), type(uint256).max);
    }

    function createOffer(address borrower, uint256 amount) external returns (uint256) {
        return offers.createOffer(borrower, amount, 10_000, 1, 1 hours);
    }
}

/// @notice Testes de falha e de borda (Semana 3): limites exatos, fronteira da validade,
/// reentrância, recebedor inválido e transições a partir de estados finais.
contract CreditInterbankOfferEdgeCasesTest is Test {
    CreditInterbankOffer internal offerContract;
    BRLToken internal brl;
    CDIPositionToken internal position;

    address internal admin = makeAddr("admin");
    address internal lender = makeAddr("bancoA");
    address internal borrower = makeAddr("bancoB");

    uint256 internal constant AMOUNT = 1_000_000_00; // R$ 1.000.000,00
    uint256 internal constant BORROWER_LIMIT = 5_000_000_00; // R$ 5.000.000,00
    uint256 internal constant RATE_100_CDI = 10_000;
    uint256 internal constant TERM_OVERNIGHT = 1;
    uint256 internal constant VALIDITY = 1 hours;

    function setUp() public {
        vm.startPrank(admin);
        brl = new BRLToken(admin);
        position = new CDIPositionToken(admin);
        offerContract = new CreditInterbankOffer(admin, brl, position);
        position.grantRole(position.MINTER_ROLE(), address(offerContract));

        offerContract.registerInstitution(lender);
        offerContract.registerInstitution(borrower);
        offerContract.setCreditLimit(borrower, BORROWER_LIMIT);
        brl.mint(lender, 10 * AMOUNT);
        vm.stopPrank();

        vm.prank(lender);
        brl.approve(address(offerContract), type(uint256).max);
    }

    function _offer(uint256 amount) internal returns (uint256 offerId) {
        vm.prank(lender);
        offerId = offerContract.createOffer(borrower, amount, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function _accept(uint256 offerId) internal {
        vm.prank(borrower);
        offerContract.acceptOffer(offerId);
    }

    function _status(uint256 offerId) internal view returns (uint256) {
        return uint256(offerContract.getOfferStatus(offerId));
    }

    function _invalidStatus(uint256 offerId, ICreditInterbankOffer.OfferStatus current)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            ICreditInterbankOffer.InvalidOfferStatus.selector,
            offerId,
            current,
            ICreditInterbankOffer.OfferStatus.Offered
        );
    }

    // ---------------------------------------------------------------------
    // Limite de crédito: valores exatos e consumo entre ofertas
    // ---------------------------------------------------------------------

    function test_Limit_OfferEqualToLimitIsAccepted() public {
        uint256 offerId = _offer(BORROWER_LIMIT);
        _accept(offerId);

        assertEq(offerContract.availableLimit(borrower), 0);
        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Settled));
    }

    function test_Limit_OneCentAboveLimitIsRejectedAtCreation() public {
        vm.prank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.InsufficientLimit.selector, borrower, BORROWER_LIMIT + 1, BORROWER_LIMIT
            )
        );
        offerContract.createOffer(borrower, BORROWER_LIMIT + 1, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function test_Limit_ConsumedByFirstSettlementBlocksSecondAccept() public {
        // Cada oferta cabe sozinha no limite, mas as duas juntas não.
        uint256 first = _offer(3_000_000_00);
        uint256 second = _offer(3_000_000_00);

        _accept(first);
        assertEq(offerContract.availableLimit(borrower), 2_000_000_00);

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICreditInterbankOffer.InsufficientLimit.selector, borrower, 3_000_000_00, 2_000_000_00
            )
        );
        offerContract.acceptOffer(second);
        assertEq(_status(second), uint256(ICreditInterbankOffer.OfferStatus.Offered));
    }

    function test_Limit_AdminCanRestoreLimitAfterSettlement() public {
        _accept(_offer(BORROWER_LIMIT));

        vm.prank(admin);
        offerContract.setCreditLimit(borrower, BORROWER_LIMIT);

        _accept(_offer(AMOUNT));
        assertEq(offerContract.availableLimit(borrower), BORROWER_LIMIT - AMOUNT);
    }

    function testFuzz_CreateOffer_RespectsBorrowerLimit(uint256 amount) public {
        amount = bound(amount, 1, 2 * BORROWER_LIMIT);
        vm.prank(lender);
        if (amount > BORROWER_LIMIT) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ICreditInterbankOffer.InsufficientLimit.selector, borrower, amount, BORROWER_LIMIT
                )
            );
        }
        offerContract.createOffer(borrower, amount, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function testFuzz_AcceptOffer_ConservesBalancesAndLimit(uint256 amount) public {
        amount = bound(amount, 1, BORROWER_LIMIT);
        uint256 lenderBefore = brl.balanceOf(lender);
        uint256 supplyBefore = brl.totalSupply();

        uint256 offerId = _offer(amount);
        _accept(offerId);

        assertEq(brl.balanceOf(lender), lenderBefore - amount);
        assertEq(brl.balanceOf(borrower), amount);
        assertEq(brl.totalSupply(), supplyBefore); // a liquidação só move BRL, não cria nem destrói
        assertEq(offerContract.availableLimit(borrower), BORROWER_LIMIT - amount);
        assertEq(position.ownerOf(offerId), lender);
    }

    // ---------------------------------------------------------------------
    // Fronteira da validade
    // ---------------------------------------------------------------------

    function test_Validity_AcceptOneSecondBeforeExpiryWorks() public {
        uint256 offerId = _offer(AMOUNT);
        vm.warp(offerContract.getOffer(offerId).expiresAt - 1);

        _accept(offerId);
        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Settled));
    }

    function test_Validity_ExpireOfferWorksExactlyAtExpiry() public {
        uint256 offerId = _offer(AMOUNT);
        vm.warp(offerContract.getOffer(offerId).expiresAt);

        offerContract.expireOffer(offerId);
        assertEq(uint256(offerContract.getOffer(offerId).status), uint256(ICreditInterbankOffer.OfferStatus.Expired));
    }

    function test_Validity_StatusStaysOfferedOneSecondBeforeExpiry() public {
        uint256 offerId = _offer(AMOUNT);
        vm.warp(offerContract.getOffer(offerId).expiresAt - 1);
        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Offered));
    }

    // ---------------------------------------------------------------------
    // Falhas na liquidação
    // ---------------------------------------------------------------------

    function test_Settlement_RevertsWhenLenderHasNoBalance() public {
        uint256 offerId = _offer(AMOUNT);
        uint256 balance = brl.balanceOf(lender);
        vm.prank(lender);
        assertTrue(brl.transfer(admin, balance)); // ofertante fica sem saldo, mas mantém o approve

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, lender, 0, AMOUNT));
        offerContract.acceptOffer(offerId);

        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(offerContract.availableLimit(borrower), BORROWER_LIMIT);
    }

    function test_Settlement_RevertsWhenLenderWasRevoked() public {
        uint256 offerId = _offer(AMOUNT);
        vm.prank(admin);
        offerContract.revokeInstitution(lender);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICreditInterbankOffer.NotRegisteredInstitution.selector, lender));
        offerContract.acceptOffer(offerId);
    }

    function test_Settlement_RevertsWhenLenderCannotReceiveNft() public {
        NonReceiverLender badLender = new NonReceiverLender(offerContract, brl);
        vm.startPrank(admin);
        offerContract.registerInstitution(address(badLender));
        brl.mint(address(badLender), AMOUNT);
        vm.stopPrank();
        uint256 offerId = badLender.createOffer(borrower, AMOUNT);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(badLender)));
        offerContract.acceptOffer(offerId);

        // Nada foi gravado: o BRL continua com o ofertante e a oferta segue aberta.
        assertEq(brl.balanceOf(address(badLender)), AMOUNT);
        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Offered));
    }

    // ---------------------------------------------------------------------
    // Reentrância
    // ---------------------------------------------------------------------

    function _reentrantLenderWithOffer() internal returns (ReentrantLender attacker, uint256 offerId) {
        attacker = new ReentrantLender(offerContract, brl);
        vm.startPrank(admin);
        offerContract.registerInstitution(address(attacker));
        brl.mint(address(attacker), 2 * AMOUNT);
        vm.stopPrank();
        offerId = attacker.createOffer(borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
    }

    function test_Reentrancy_AcceptDuringSettlementIsBlocked() public {
        (ReentrantLender attacker, uint256 offerId) = _reentrantLenderWithOffer();
        uint256 otherOfferId = attacker.createOffer(borrower, AMOUNT, RATE_100_CDI, TERM_OVERNIGHT, VALIDITY);
        attacker.setAttack(ReentrantLender.Attack.AcceptOther, otherOfferId);

        vm.prank(borrower);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        offerContract.acceptOffer(offerId);

        // A tentativa desfez a transação inteira: nenhuma das duas ofertas foi liquidada.
        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(_status(otherOfferId), uint256(ICreditInterbankOffer.OfferStatus.Offered));
        assertEq(brl.balanceOf(borrower), 0);
    }

    function test_Reentrancy_CancelDuringSettlementSeesSettledState() public {
        // O estado é gravado antes das transferências (checks-effects-interactions):
        // quando o ofertante tenta cancelar no meio da liquidação, a oferta já está Liquidada.
        (ReentrantLender attacker, uint256 offerId) = _reentrantLenderWithOffer();
        attacker.setAttack(ReentrantLender.Attack.CancelSame, offerId);

        vm.prank(borrower);
        vm.expectRevert(_invalidStatus(offerId, ICreditInterbankOffer.OfferStatus.Settled));
        offerContract.acceptOffer(offerId);

        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Offered));
    }

    function test_Reentrancy_HonestContractLenderSettlesNormally() public {
        (ReentrantLender attacker, uint256 offerId) = _reentrantLenderWithOffer();
        attacker.setAttack(ReentrantLender.Attack.None, 0);

        _accept(offerId);
        assertEq(position.ownerOf(offerId), address(attacker));
    }

    // ---------------------------------------------------------------------
    // Estados finais e ofertas inexistentes
    // ---------------------------------------------------------------------

    function test_FinalStates_RejectedOfferCannotBeCancelled() public {
        uint256 offerId = _offer(AMOUNT);
        vm.prank(borrower);
        offerContract.rejectOffer(offerId);

        vm.prank(lender);
        vm.expectRevert(_invalidStatus(offerId, ICreditInterbankOffer.OfferStatus.Rejected));
        offerContract.cancelOffer(offerId);
    }

    function test_FinalStates_CancelledOfferCannotBeRejected() public {
        uint256 offerId = _offer(AMOUNT);
        vm.prank(lender);
        offerContract.cancelOffer(offerId);

        vm.prank(borrower);
        vm.expectRevert(_invalidStatus(offerId, ICreditInterbankOffer.OfferStatus.Cancelled));
        offerContract.rejectOffer(offerId);
    }

    function test_FinalStates_SettledOfferCannotExpire() public {
        uint256 offerId = _offer(AMOUNT);
        _accept(offerId);
        vm.warp(block.timestamp + VALIDITY + 1);

        vm.expectRevert(_invalidStatus(offerId, ICreditInterbankOffer.OfferStatus.Settled));
        offerContract.expireOffer(offerId);
        assertEq(_status(offerId), uint256(ICreditInterbankOffer.OfferStatus.Settled));
    }

    function test_FinalStates_ExpiredOfferCannotBeExpiredTwice() public {
        uint256 offerId = _offer(AMOUNT);
        vm.warp(block.timestamp + VALIDITY);
        offerContract.expireOffer(offerId);

        vm.expectRevert(_invalidStatus(offerId, ICreditInterbankOffer.OfferStatus.Expired));
        offerContract.expireOffer(offerId);
    }

    function test_UnknownOffer_AllActionsRevertWithOfferNotFound() public {
        bytes memory notFound = abi.encodeWithSelector(ICreditInterbankOffer.OfferNotFound.selector, 99);

        vm.startPrank(borrower);
        vm.expectRevert(notFound);
        offerContract.acceptOffer(99);
        vm.expectRevert(notFound);
        offerContract.rejectOffer(99);
        vm.stopPrank();

        vm.prank(lender);
        vm.expectRevert(notFound);
        offerContract.cancelOffer(99);

        vm.expectRevert(notFound);
        offerContract.expireOffer(99);
        vm.expectRevert(notFound);
        offerContract.getOfferStatus(99);
    }

    function test_OfferIds_AreSequentialAndUnique() public {
        assertEq(_offer(AMOUNT), 1);
        assertEq(_offer(AMOUNT), 2);
        assertEq(_offer(AMOUNT), 3);
    }
}
