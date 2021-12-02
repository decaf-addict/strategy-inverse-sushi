// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import "../interfaces/Inverse.sol";
import "../interfaces/Uniswap.sol";


interface ISushiBar is IERC20 {
    function sushi() external returns (address);

    function enter(uint _amount) external;

    function leave(uint _share) external;
}

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint;

    IERC20 public constant sushi = IERC20(0x6B3595068778DD592e39A122f4f5a5cF09C90fE2);
    IERC20 public constant reward = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    ISushiBar public constant xSushi = ISushiBar(0x8798249c2E607446EfB7Ad49eC89dD1865Ff4272);
    ICERC20 public constant anXSushi = ICERC20(0xD60B06B457bFf7fc38AC5E7eCE2b5ad16B288326);
    IERC20 public constant weth = IERC20(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    IUniswapV2Router02 constant public sushiswapRouter = IUniswapV2Router02(address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F));
    IUniswapV2Router02 constant public uniswapRouter = IUniswapV2Router02(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
    IUniswapV2Router02 public router = sushiswapRouter;
    IUnitroller public comptroller;

    address[] path;
    uint constant private max = type(uint).max;

    constructor(address _vault) public BaseStrategy(_vault) {
        require(xSushi.sushi() == address(sushi));
        comptroller = IUnitroller(anXSushi.comptroller());

        address[] memory markets = new address[](1);
        markets[0] = address(anXSushi);
        comptroller.enterMarkets(markets);

        path = [address(reward), address(weth), address(want)];
        sushi.approve(address(xSushi), max);
        xSushi.approve(address(anXSushi), max);
        reward.approve(address(uniswapRouter), max);
        reward.approve(address(sushiswapRouter), max);
    }

    // BASESTRATEGY

    function name() external view override returns (string memory) {
        return "StrategyInverseSushi";
    }

    function estimatedTotalAssets() public view override returns (uint) {
        uint anXSushiInXSushi = balanceOfAnXSushi().mul(xSushiPerAnXSushi()).div(1e18);
        uint totalInXSushi = balanceOfXSushi().add(anXSushiInXSushi);
        uint totalInWants = totalInXSushi.mul(sushiPerXSushi()).div(1e18);
        uint wants = balanceOfWant().add(totalInWants);
        return wants;
    }

    function prepareReturn(uint _debtOutstanding) internal override returns (uint _profit, uint _loss, uint _debtPayment){
        if (_debtOutstanding > 0) {
            (_debtPayment, _loss) = liquidatePosition(_debtOutstanding);
        }

        uint before = balanceOfWant();

        // redeem lending profit from anXSushi to xSushi
        uint eta = estimatedTotalAssets();
        uint debt = vault.strategies(address(this)).totalDebt;
        uint lendingProfitSushi = eta > debt ? eta.sub(debt) : 0;
        uint lendingProfitXSushi = lendingProfitSushi.mul(1e18).div(sushiPerXSushi());
        _redeemUnderlying(lendingProfitXSushi);

        // return xSushi for sushi
        _leaveSushiBar(balanceOfXSushi());

        // sell inv rewards for sushi
        _claimRewards();
        _sellRewards(balanceOfReward());

        _profit += balanceOfWant().sub(before);

        // net out PnL
        if (_profit > _loss) {
            _profit = _profit.sub(_loss);
            _loss = 0;
        } else {
            _loss = _loss.sub(_profit);
            _profit = 0;
        }
    }

    function adjustPosition(uint _debtOutstanding) internal override {
        xSushi.enter(balanceOfWant());
        anXSushi.mint(balanceOfXSushi());
    }

    function liquidatePosition(uint _amountNeeded) internal override returns (uint _liquidatedAmount, uint _loss){
        uint totalAssets = balanceOfWant();

        if (_amountNeeded > totalAssets) {
            uint toExitSushi = _amountNeeded.sub(totalAssets);
            uint toExitXSushi = toExitSushi.mul(1e18).div(sushiPerXSushi());
            uint exitable = Math.min(toExitXSushi, anXSushi.balanceOfUnderlying(address(this)));
            anXSushi.redeemUnderlying(exitable);
            _leaveSushiBar(balanceOfXSushi());
            _liquidatedAmount = Math.min(balanceOfWant(), _amountNeeded);
            _loss = _amountNeeded > _liquidatedAmount ? _amountNeeded.sub(_liquidatedAmount) : 0;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function liquidateAllPositions() internal override returns (uint _amountFreed) {
        anXSushi.redeem(balanceOfAnXSushi());
        _leaveSushiBar(balanceOfXSushi());
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        xSushi.transfer(_newStrategy, balanceOfXSushi());
        anXSushi.transfer(_newStrategy, balanceOfAnXSushi());
        reward.transfer(_newStrategy, balanceOfReward());
    }

    function protectedTokens() internal view override returns (address[] memory){}

    function ethToWant(uint _amtInWei) public view virtual override returns (uint){return _amtInWei;}

    // INTERNAL
    // claim inv
    function claimRewards() external onlyVaultManagers {
        _claimRewards();
    }

    function _claimRewards() internal {
        if (comptroller.compAccrued(address(this)) > 0) {
            comptroller.claimComp(address(this));
        }
    }

    // sell inv for sushi
    function sellRewards(uint _amount) external onlyVaultManagers {
        _sellRewards(_amount);
    }

    function _sellRewards(uint _amount) internal {
        if (_amount > 0) {
            router.swapExactTokensForTokens(_amount, uint256(0), path, address(this), now);
        }
    }

    // redeem anXSushi for xSushi
    function redeemUnderlying(uint _amountXSushi) external onlyVaultManagers {
        _redeemUnderlying(_amountXSushi);
    }

    function _redeemUnderlying(uint _amountXSushi) internal {
        if (_amountXSushi > 0) {
            anXSushi.redeemUnderlying(_amountXSushi);
        }
    }

    // return xSushi for sushi
    function leaveSushiBar(uint _amountXSushi) external onlyVaultManagers {
        _leaveSushiBar(_amountXSushi);
    }

    function _leaveSushiBar(uint _amountXSushi) internal {
        if (_amountXSushi > 0) {
            xSushi.leave(_amountXSushi);
        }
    }


    // HELPERS
    function balanceOfWant() public view returns (uint){
        return sushi.balanceOf(address(this));
    }

    function balanceOfXSushi() public view returns (uint){
        return xSushi.balanceOf(address(this));
    }

    function balanceOfAnXSushi() public view returns (uint){
        return anXSushi.balanceOf(address(this));
    }

    function balanceOfReward() public view returns (uint){
        return reward.balanceOf(address(this));
    }

    function sushiPerXSushi() public view returns (uint){
        uint stakedSushi = sushi.balanceOf(address(xSushi));
        uint totalXSushi = xSushi.totalSupply();
        return stakedSushi.mul(1e18).div(totalXSushi);
    }

    function xSushiPerAnXSushi() public view returns (uint) {
        return anXSushi.exchangeRateStored();
    }


    // SETTERS
    function switchDex(bool isUniswap) external onlyVaultManagers {
        if (isUniswap) router = uniswapRouter;
        else router = sushiswapRouter;
    }

    function updateComptroller() external onlyVaultManagers {
        address[] memory markets = new address[](1);
        markets[0] = address(anXSushi);
        comptroller.exitMarket(markets);
        comptroller = IUnitroller(anXSushi.comptroller());
        comptroller.enterMarkets(markets);
    }
}
