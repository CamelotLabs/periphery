pragma solidity ^0.6.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPriceConsumer.sol";
import './libraries/SafeMath.sol';
import "excalibur-core//contracts/interfaces/IExcaliburV2Pair.sol";
import "excalibur-core//contracts/interfaces/IExcaliburV2Factory.sol";
import "excalibur-core//contracts/interfaces/IERC20.sol";

contract PriceConsumerV3 is IPriceConsumer{
  using SafeMath for uint;

  address public owner;
  address public factory;

  address public immutable override USD;
  address public immutable override WETH;
  address public immutable override EXC;

  // [tokenAddress][quoteAddress] = priceFeederAddress => quoteAddress (WBNB,BUSD)
  mapping (address => mapping(address=> address)) tokenPriceFeeder;

  constructor(address _factory, address _WETH, address _USD, address _EXC) public {
    owner = msg.sender;
    factory = _factory;
    WETH = _WETH;
    USD = _USD;
    EXC = _EXC;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(owner == msg.sender, "ExcaliburV2Factory: caller is not the owner");
    _;
  }

  function setOwner(address _owner) external onlyOwner {
      owner = _owner;
  }

  function addTokenPriceFeeder(address token, address quote, address priceFeeder) external onlyOwner {
    require(quote == USD || quote == WETH, "PriceConsumerV3: invalid quote");
    tokenPriceFeeder[token][quote] = priceFeeder;
  }

  function getTokenFairPriceUSD(address token) public virtual override view returns (uint) {
    return _getTokenFairPriceUSD(token);
  }

  function getWETHFairPriceUSD() public view virtual override returns (uint){
    return _getWETHFairPriceUSD();
  }

  function getEXCPriceUSD() external view virtual override returns (uint valueInUSD) {
    return _getEXCPriceUSD();
  }

  function valueOfTokenUSD(address token) external view virtual override returns (uint valueInUSD){
    if(token == WETH) return _getWETHFairPriceUSD();
    else if (token == USD) return 1e18;
    else if (token == EXC) return _getEXCPriceUSD();
    else return _getTokenFairPriceUSD(token);
  }

  /**
   * Returns the latest price in USD
   */
  function _getTokenFairPriceUSD(address token) internal view returns (uint) {
    address quote = tokenPriceFeeder[token][USD] != address(0) ? USD : WETH;
    address priceFeeder = tokenPriceFeeder[token][quote];

    if (priceFeeder == address(0)) return 0; // No priceFeeder available

    uint priceDecimals = uint(AggregatorV3Interface(priceFeeder).decimals());
    (,int price,,,) = AggregatorV3Interface(priceFeeder).latestRoundData();
    uint valueInBUSD = 0;
    if(priceDecimals <= 18){
      valueInBUSD = uint(price).mul(10**(18 - priceDecimals));
    }
    else {
      valueInBUSD = uint(price) / (10**(priceDecimals - 18));
    }

    if(quote == WETH){
      return valueInBUSD.mul(_getWETHFairPriceUSD()) / 1e18;
    }
    return valueInBUSD;
  }

  function _getWETHFairPriceUSD() internal view returns (uint){
    address priceFeeder = tokenPriceFeeder[WETH][USD];
    uint priceDecimals = uint(AggregatorV3Interface(priceFeeder).decimals());
    (,int price,,,) = AggregatorV3Interface(priceFeeder).latestRoundData();
    uint valueInBUSD = 0;
    if(priceDecimals <= 18){
      valueInBUSD = uint(price).mul(10**(18 - priceDecimals));
    }
    else {
      valueInBUSD = uint(price) / (10**(priceDecimals - 18));
    }
    return valueInBUSD;
  }

  function _getEXCPriceUSD() internal view returns (uint) {
    IExcaliburV2Pair pair = IExcaliburV2Pair(IExcaliburV2Factory(factory).getPair(EXC, USD));
    uint usdDecimals = IERC20(USD).decimals();

    (uint reserve0, uint reserve1,) = pair.getReserves();
    if (pair.token0() == USD) {
      if(usdDecimals <= 18){
        reserve0 = reserve0.mul(10**(18 - usdDecimals));
      }
      else {
        reserve0 = reserve0 / (10**(usdDecimals - 18));
      }
      return reserve0.mul(1e18) / reserve1;
    }

    if(usdDecimals <= 18){
      reserve1 = reserve1.mul(10**(18 - usdDecimals));
    }
    else {
      reserve1 = reserve1 / (10**(usdDecimals - 18));
    }
    return reserve1.mul(1e18) / reserve0;
  }
}
