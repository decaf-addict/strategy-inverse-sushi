// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.6.0 <0.7.0;
pragma experimental ABIEncoderV2;

interface PriceOracle {
    /**
      * @notice Get the underlying price of a cToken asset
      * @param cToken The cToken to get the underlying price of
      * @return The underlying asset price mantissa (scaled by 1e18).
      *  Zero means the price is unavailable.
      */
    function getUnderlyingPrice(address cToken) external view returns (uint);
}

interface IUnitroller {
    // autogen getter
    function oracle() external view returns (PriceOracle);

    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);

    function exitMarket(address cToken) external returns (uint);

    /*** Policy Hooks ***/

    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint);

    function mintVerify(address cToken, address minter, uint mintAmount, uint mintTokens) external;

    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (uint);

    function redeemVerify(address cToken, address redeemer, uint redeemAmount, uint redeemTokens) external;

    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint);

    function borrowVerify(address cToken, address borrower, uint borrowAmount) external;

    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount) external returns (uint);

    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex) external;

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint);

    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens) external;

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint);

    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external;

    function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (uint);

    function transferVerify(address cToken, address src, address dst, uint transferTokens) external;

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint repayAmount) external view returns (uint, uint);

    function markets(address cToken) external view returns (bool isListed, uint256 collatFactorMantissa, bool isComped);

    function compAccrued(address holder) external view returns (uint256 amount);

    function claimComp(address holder, address[] memory cTokens) external;

    function claimComp(address holder) external;

    function getAccountLiquidity(address account) external view returns (uint error, uint liquidity, uint shortfall);

}

interface CTokenStorage {
}

interface ICToken {
    function comptroller() external view returns (address);

    /*** Market Events ***/

    /**
     * @dev Event emitted when interest is accrued
     */
    event AccrueInterest(uint cashPrior, uint interestAccumulated, uint borrowIndex, uint totalBorrows);

    /**
     * @dev Event emitted when tokens are minted
     */
    event Mint(address minter, uint mintAmount, uint mintTokens);

    /**
     * @dev Event emitted when tokens are redeemed
     */
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

    /**
     * @dev Event emitted when underlying is borrowed
     */
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @dev Event emitted when a borrow is repaid
     */
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);

    /**
     * @dev Event emitted when a borrow is liquidated
     */
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address cTokenCollateral, uint seizeTokens);


    /*** Admin Events ***/

    /**
     * @dev Event emitted when pendingAdmin is changed
     */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
     * @dev Event emitted when pendingAdmin is accepted, which means admin is updated
     */
    event NewAdmin(address oldAdmin, address newAdmin);

    /**
     * @dev Event emitted when comptroller is changed
     */
    event NewComptroller(IUnitroller oldComptroller, IUnitroller newComptroller);

    /**
     * @dev Event emitted when interestRateModel is changed
     */
    event NewMarketInterestRateModel(InterestRateModel oldInterestRateModel, InterestRateModel newInterestRateModel);

    /**
     * @dev Event emitted when the reserve factor is changed
     */
    event NewReserveFactor(uint oldReserveFactorMantissa, uint newReserveFactorMantissa);

    /**
     * @dev Event emitted when the reserves are added
     */
    event ReservesAdded(address benefactor, uint addAmount, uint newTotalReserves);

    /**
     * @dev Event emitted when the reserves are reduced
     */
    event ReservesReduced(address admin, uint reduceAmount, uint newTotalReserves);

    /**
     * @dev EIP20 Transfer event
     */
    event Transfer(address indexed from, address indexed to, uint amount);

    /**
     * @dev EIP20 Approval event
     */
    event Approval(address indexed owner, address indexed spender, uint amount);

    /**
     * @dev Failure event
     */
    event Failure(uint error, uint info, uint detail);


    /*** User Interface ***/
    function decimals() external view returns (uint8);

    function transfer(address dst, uint amount) external returns (bool);

    function transferFrom(address src, address dst, uint amount) external returns (bool);

    function approve(address spender, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint); // changed to view

    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);

    function borrowRatePerBlock() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);

    function totalBorrowsCurrent() external returns (uint);

    function borrowBalanceCurrent(address account) external returns (uint);

    function borrowBalanceStored(address account) external view returns (uint);

    function exchangeRateCurrent() external returns (uint);

    // underlying per c
    function exchangeRateStored() external view returns (uint);

    function getCash() external view returns (uint);

    function accrueInterest() external returns (uint);

    function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint);

    function underlying() external view returns (address);

    /*** Admin Functions ***/

    function _setPendingAdmin(address payable newPendingAdmin) external returns (uint);

    function _acceptAdmin() external returns (uint);

    function _setComptroller(IUnitroller newComptroller) external returns (uint);

    function _setReserveFactor(uint newReserveFactorMantissa) external returns (uint);

    function _reduceReserves(uint reduceAmount) external returns (uint);

    function _setInterestRateModel(InterestRateModel newInterestRateModel) external returns (uint);


}


interface ICERC20 is ICToken {

    /*** User Interface ***/
    function mint(uint mintAmount) external returns (uint);

    //
    function redeem(uint cTokensIn) external returns (uint);

    function redeemUnderlying(uint underlyingOut) external returns (uint256);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow(uint repayAmount) external returns (uint);

    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);

    function liquidateBorrow(address borrower, uint repayAmount, ICToken cTokenCollateral) external returns (uint);

    /*** Admin Functions ***/

    function _addReserves(uint addAmount) external returns (uint);
}


interface CDelegatorInterface {
    /**
     * @dev Emitted when implementation is changed
     */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
     * @dev Called by the admin to update the implementation of the delegator
     * @param implementation_ The address of the new implementation for delegation
     * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation
     * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
     */
    function _setImplementation(address implementation_, bool allowResign, bytes memory becomeImplementationData) external;
}

interface CDelegateInterface {
    /**
     * @dev Called by the delegator on a delegate to initialize it for duty
     * @dev Should revert if any issues arise which make it unfit for delegation
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) external;

    /**
     * @dev Called by the delegator on a delegate to forfeit its responsibility
     */
    function _resignImplementation() external;
}

interface InterestRateModel {
    /**
      * @dev Calculates the current borrow interest rate per block
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @param reserves The total amount of reserves the market has
      * @return The borrow rate per block (as a percentage, and scaled by 1e18)
      */
    function getBorrowRate(uint cash, uint borrows, uint reserves) external view returns (uint);

    /**
      * @dev Calculates the current supply interest rate per block
      * @param cash The total amount of cash the market has
      * @param borrows The total amount of borrows the market has outstanding
      * @param reserves The total amount of reserves the market has
      * @param reserveFactorMantissa The current reserve factor the market has
      * @return The supply rate per block (as a percentage, and scaled by 1e18)
      */
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) external view returns (uint);

}

interface TimelockEscrowInterface {
    function withdraw() external;
}