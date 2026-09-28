// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ICreditInterbankOffer
/// @notice Interface do protocolo de crédito interfinanceiro overnight.
/// @dev Escopo reduzido (Semana 3): ofertas direcionadas, rejeição, cadastro de carteiras
/// autorizadas, limite por instituição e liquidação DvP (BRL tokenizado contra NFT de posição).
/// Unidades:
/// - `amount`: BRL tokenizado em centavos (o token tem 2 casas decimais).
/// - `rateCDI`: percentual do CDI em pontos-base (10_000 = 100% do CDI).
/// - `term`: prazo do empréstimo em dias (1 = overnight).
/// - `validityWindow` / `expiresAt` / timestamps: segundos Unix (`block.timestamp`).
interface ICreditInterbankOffer {
    /// @dev A ordem dos valores é estável: novos estados entram sempre no final
    /// (Offered=0, Accepted=1, Settled=2, Cancelled=3, Expired=4, Rejected=5).
    enum OfferStatus {
        Offered,
        Accepted,
        Settled,
        Cancelled,
        Expired,
        Rejected
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

    // ---------------------------------------------------------------------
    // Eventos de cadastro e limite
    // ---------------------------------------------------------------------

    event InstitutionRegistered(address indexed wallet, uint256 timestamp);
    event InstitutionRevoked(address indexed wallet, uint256 timestamp);
    event CreditLimitUpdated(address indexed institution, uint256 previousLimit, uint256 newLimit, uint256 timestamp);

    // ---------------------------------------------------------------------
    // Eventos do ciclo de vida da oferta
    // ---------------------------------------------------------------------

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
    /// @notice Emitido na mesma transação de `OfferAccepted`, depois da troca DvP.
    /// Carrega os dados exigidos pelo RNF03 (partes, valor, taxa) e o id do NFT de posição.
    event OfferSettled(
        uint256 indexed offerId,
        address indexed lender,
        address indexed borrower,
        uint256 amount,
        uint256 rateCDI,
        uint256 term,
        uint256 positionTokenId,
        uint256 timestamp
    );
    event OfferRejected(uint256 indexed offerId, address indexed borrower, uint256 timestamp);
    event OfferCancelled(uint256 indexed offerId, uint256 timestamp);
    event OfferExpired(uint256 indexed offerId, uint256 timestamp);

    // ---------------------------------------------------------------------
    // Erros
    // ---------------------------------------------------------------------

    error InsufficientLimit(address borrower, uint256 requested, uint256 available);
    error OfferNotFound(uint256 offerId);
    error InvalidOfferStatus(uint256 offerId, OfferStatus current, OfferStatus expected);
    error NotOfferOwner(uint256 offerId, address caller);
    error NotEligibleBorrower(uint256 offerId, address caller);
    error InvalidOfferParameters(uint256 amount, uint256 rateCDI, uint256 term);
    error InvalidValidityWindow(uint256 validityWindow);
    error OfferHasExpired(uint256 offerId, uint256 expiresAt);
    error OfferNotYetExpired(uint256 offerId, uint256 expiresAt);
    error NotRegisteredInstitution(address account);
    error InvalidCounterparty(address lender, address borrower);
    error ZeroAddress();

    // ---------------------------------------------------------------------
    // Administração (papel DEFAULT_ADMIN_ROLE)
    // ---------------------------------------------------------------------

    /// @notice Autoriza a carteira de uma instituição a operar no protocolo.
    function registerInstitution(address wallet) external;
    /// @notice Remove a autorização da carteira. Ofertas abertas com ela deixam de poder ser aceitas.
    function revokeInstitution(address wallet) external;
    /// @notice Define o limite de crédito disponível da instituição (em centavos de BRL tokenizado).
    /// @dev Sem D+1 no escopo, o limite consumido na liquidação é recomposto pelo admin por esta função.
    function setCreditLimit(address institution, uint256 newLimit) external;

    // ---------------------------------------------------------------------
    // Ciclo de vida da oferta
    // ---------------------------------------------------------------------

    /// @param borrower carteira autorizada do banco tomador (oferta direcionada).
    /// @param validityWindow segundos, a partir da criação, em que a oferta pode ser aceita,
    /// rejeitada ou cancelada; independente de `term`, que é o prazo do empréstimo.
    function createOffer(address borrower, uint256 amount, uint256 rateCDI, uint256 term, uint256 validityWindow)
        external
        returns (uint256 offerId);
    /// @notice Tomador aceita a oferta. Na mesma transação: valida limite, transfere o BRL tokenizado
    /// do ofertante para o tomador e emite o NFT de posição para o ofertante (DvP).
    function acceptOffer(uint256 offerId) external;
    /// @notice Tomador recusa a oferta antes do vencimento. Estado final.
    function rejectOffer(uint256 offerId) external;
    /// @notice Ofertante retira a oferta antes do aceite e do vencimento. Estado final.
    function cancelOffer(uint256 offerId) external;
    /// @notice Transição sem permissão que grava `Offered -> Expired` quando
    /// `block.timestamp >= expiresAt`. Reverte se chamada antes do vencimento ou em outro estado.
    function expireOffer(uint256 offerId) external;

    // ---------------------------------------------------------------------
    // Leitura
    // ---------------------------------------------------------------------

    function getOffer(uint256 offerId) external view returns (Offer memory);
    /// @notice Retorna `Expired` assim que a janela de validade passa, mesmo que `expireOffer`
    /// ainda não tenha sido chamada para gravar a transição on-chain.
    function getOfferStatus(uint256 offerId) external view returns (OfferStatus);
    function availableLimit(address institution) external view returns (uint256);
    function isRegisteredInstitution(address account) external view returns (bool);
}
