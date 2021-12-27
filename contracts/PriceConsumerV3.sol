pragma solidity ^0.6.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPriceConsumer.sol";
import './libraries/SafeMath.sol';
import "excalibur-core/contracts/interfaces/IExcaliburV2Pair.sol";
import "excalibur-core/contracts/interfaces/IExcaliburV2Factory.sol";
import "excalibur-core/contracts/interfaces/IERC20.sol";

contract PriceConsumerV3 is IPriceConsumer {
  using SafeMath for uint;

  address public owner;
  address public factory;

  address public immutable override USD; // stable usd coin, will be adapted depending on the used chain
  address public immutable override WETH;
  address public immutable override EXC;

  uint public lastEXCPrice;

  // [tokenAddress][quoteAddress] = priceFeederAddress => quoteAddress (WETH,USD)
  mapping(address => mapping(address => address)) public tokenPriceFeeder;

  event SetLastEXCPrice(uint lastEXCPrice, uint newPrice);
  event SetWhitelistToken(address token, bool isWhitelisted);
  event SetOwner(address prevOwner, address newOwner);
  event SetTokenPriceFeeder(address token, address quote, address priceFeeder);

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
    require(owner == msg.sender, "PriceConsumerV3: caller is not the owner");
    _;
  }

  function getTokenFairPriceUSD(address token) external override view returns (uint) {
    return _getTokenFairPriceUSD(token);
  }

  function getTokenPriceUSDUsingPair(address token) external override view returns (uint){
    return _getTokenPriceUSDUsingPair(token);
  }

  function getTokenMinPriceUSD(address token) external override view returns (uint) {
    if (token == USD) return 1e18;

    uint fairPriceUSD = _getTokenFairPriceUSD(token);
    if (fairPriceUSD == 0) return 0;
    // Only manage tokens from which a fair price can be fetch
    uint calculatedPriceUSD = _getTokenPriceUSDUsingPair(token);
    if (calculatedPriceUSD == 0) return 0;
    return fairPriceUSD < calculatedPriceUSD ? fairPriceUSD : calculatedPriceUSD;
  }

  function getEXCMaxPriceUSD() external override returns (uint){
    uint calculatedPriceUSD = _getTokenPriceUSDUsingPair(EXC);
    if (lastEXCPrice < calculatedPriceUSD) {
      emit SetLastEXCPrice(lastEXCPrice, calculatedPriceUSD);
      lastEXCPrice = calculatedPriceUSD;
    }
    return lastEXCPrice;
  }

  function valueOfTokenUSD(address token) external view override returns (uint valueInUSD) {
    return _valueOfTokenUSD(token);
  }

  function setTokenPriceFeeder(address token, address quote, address priceFeeder) external onlyOwner {
    require(quote == USD || quote == WETH, "PriceConsumerV3: invalid quote");
    tokenPriceFeeder[token][quote] = priceFeeder;
    emit SetTokenPriceFeeder(token, quote, priceFeeder);
  }

  function setLastEXCPrice(uint price) external onlyOwner {
    emit SetLastEXCPrice(lastEXCPrice, price);
    lastEXCPrice = price;
  }

  function setOwner(address _owner) external onlyOwner {
    emit SetOwner(owner, _owner);
    owner = _owner;
  }

  function _valueOfTokenUSD(address token) internal view returns (uint valueInUSD) {
    if (token == WETH) return _getWETHFairPriceUSD();
    if (token == USD) return 1e18;

    uint fairPrice = _getTokenFairPriceUSD(token);
    if (fairPrice > 0) return fairPrice;

    return _getTokenPriceUSDUsingPair(token);
  }

  /**
   * @dev Returns the token latest price in USD based on priceFeeder
   */
  function _getTokenFairPriceUSD(address token) internal view returns (uint) {
    address quote = tokenPriceFeeder[token][USD] != address(0) ? USD : WETH;
    address priceFeeder = tokenPriceFeeder[token][quote];

    // no priceFeeder available
    if (priceFeeder == address(0)) return 0;

    uint priceDecimals = uint(AggregatorV3Interface(priceFeeder).decimals());
    (,int price,,,) = AggregatorV3Interface(priceFeeder).latestRoundData();
    if (price <= 0) return 0;

    uint valueInUSD = 0;

    // check if price decimals is 18 like the EXC token and adjust it for conversion
    if (priceDecimals <= 18) {
      valueInUSD = uint(price).mul(10 ** (18 - priceDecimals));
    }
    else {
      valueInUSD = uint(price) / (10 ** (priceDecimals - 18));
    }

    if (quote == WETH) {
      return valueInUSD.mul(_getWETHFairPriceUSD()) / 1e18;
    }
    return valueInUSD;
  }

  /**
   * @dev Returns the WETH latest price in USD based on priceFeeder
   */
  function _getWETHFairPriceUSD() internal view returns (uint){
    address priceFeeder = tokenPriceFeeder[WETH][USD];
    if (priceFeeder == address(0)) return _getTokenPriceUSDUsingPair(WETH);

    uint priceDecimals = uint(AggregatorV3Interface(priceFeeder).decimals());
    (,int price,,,) = AggregatorV3Interface(priceFeeder).latestRoundData();
    if (price <= 0) return 0;

    uint valueInUSD = 0;
    if (priceDecimals <= 18) {
      valueInUSD = uint(price).mul(10 ** (18 - priceDecimals));
    }
    else {
      valueInUSD = uint(price) / (10 ** (priceDecimals - 18));
    }
    return valueInUSD;
  }

  /**
   * @dev Returns the token latest price in USD based on pair
   *
   * Called if no priceFeeder is available for this token
   */
  function _getTokenPriceUSDUsingPair(address token) internal view returns (uint){
    address quote = USD;
    address _pair = IExcaliburV2Factory(factory).getPair(token, quote);
    if (_pair == address(0)) {
      if (token == WETH) return 0;

      quote = WETH;
      _pair = IExcaliburV2Factory(factory).getPair(token, quote);
      if (_pair == address(0)) return 0;
    }
    IExcaliburV2Pair pair = IExcaliburV2Pair(_pair);

    uint quoteDecimals = IERC20(quote).decimals();

    (uint reserve0, uint reserve1,) = pair.getReserves();
    if (reserve0 == 0 || reserve1 == 0) return 0;

    uint priceInQuote = 0;
    // check if price decimals is 18 like the EXC token and adjust it for conversion
    address token0 = pair.token0();
    if (token0 == quote) {
      uint token1Decimals = IERC20(pair.token1()).decimals();
      if (quoteDecimals <= 18) {
        reserve0 = reserve0.mul(10 ** (18 - quoteDecimals));
      }
      else {
        reserve0 = reserve0 / (10 ** (quoteDecimals - 18));
      }
      priceInQuote = reserve0.mul(10 ** token1Decimals) / reserve1;
    }
    else {
      uint token0Decimals = IERC20(token0).decimals();
      if (quoteDecimals <= 18) {
        reserve1 = reserve1.mul(10 ** (18 - quoteDecimals));
      }
      else {
        reserve1 = reserve1 / (10 ** (quoteDecimals - 18));
      }
      priceInQuote = reserve1.mul(10 ** token0Decimals) / reserve0;
    }

    if (quote == WETH) {
      return priceInQuote.mul(_getWETHFairPriceUSD()) / 1e18;
    }
    return priceInQuote;
  }
}
