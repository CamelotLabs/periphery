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
  
  mapping(address => bool) whitelistedTokens; // trustable tokens for transaction fee mining

  // [tokenAddress][quoteAddress] = priceFeederAddress => quoteAddress (WETH,USD)
  mapping(address => mapping(address => address)) public tokenPriceFeeder;

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

  function isWhitelistedToken(address token) external view override returns (bool isWhitelisted) {
    return whitelistedTokens[token];
  }

  function getTokenFairPriceUSD(address token) public override view returns (uint) {
    return _getTokenFairPriceUSD(token);
  }

  function getWETHFairPriceUSD() public view override returns (uint){
    return _getWETHFairPriceUSD();
  }

  function getEXCPriceUSD() external view override returns (uint valueInUSD) {
    return _getTokenPriceUSDUsingPair(EXC);
  }

  function valueOfToTokenUSD(address fromToken, address toToken) external view override returns(uint valueInUSD) {
    if(!whitelistedTokens[fromToken] || !whitelistedTokens[toToken]) return 0;
    return _valueOfTokenUSD(toToken);
  }

  function valueOfTokenUSD(address token) external view override returns (uint valueInUSD) {
    return _valueOfTokenUSD(token);
  }

  function _valueOfTokenUSD(address token) internal view returns (uint valueInUSD) {
    if (token == WETH) return _getWETHFairPriceUSD();
    if (token == USD) return 1e18;
    if (token == EXC) return _getTokenPriceUSDUsingPair(token);

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
      if(token == WETH) return 0;

      quote = WETH;
      _pair = IExcaliburV2Factory(factory).getPair(token, quote);
      if (_pair == address(0)) return 0;
    }
    IExcaliburV2Pair pair = IExcaliburV2Pair(_pair);

    uint quoteDecimals = IERC20(quote).decimals();

    (uint reserve0, uint reserve1,) = pair.getReserves();
    if(reserve0 == 0 || reserve1 == 0) return 0;

    uint priceInQuote = 0;
    // check if price decimals is 18 like the EXC token and adjust it for conversion
    if (pair.token0() == quote) {
      if (quoteDecimals <= 18) {
        reserve0 = reserve0.mul(10 ** (18 - quoteDecimals));
      }
      else {
        reserve0 = reserve0 / (10 ** (quoteDecimals - 18));
      }
      priceInQuote = reserve0.mul(1e18) / reserve1;
    }
    else{
      if (quoteDecimals <= 18) {
      reserve1 = reserve1.mul(10 ** (18 - quoteDecimals));
      }
      else {
        reserve1 = reserve1 / (10 ** (quoteDecimals - 18));
      }
      priceInQuote = reserve1.mul(1e18) / reserve0;
    }

    if (quote == WETH) {
      return priceInQuote.mul(_getWETHFairPriceUSD()) / 1e18;
    }
    return priceInQuote;
  }

  function setOwner(address _owner) external onlyOwner {
    emit SetOwner(owner, _owner);
    owner = _owner;
  }

  function setWhitelistToken(address token, bool whitelist) external onlyOwner {
    whitelistedTokens[token] = whitelist;
    emit SetWhitelistToken(token, whitelist);
  }

  function setTokenPriceFeeder(address token, address quote, address priceFeeder) external onlyOwner {
    require(quote == USD || quote == WETH, "PriceConsumerV3: invalid quote");
    tokenPriceFeeder[token][quote] = priceFeeder;
    emit SetTokenPriceFeeder(token, quote, priceFeeder);
  }
}
