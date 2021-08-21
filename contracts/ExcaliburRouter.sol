pragma solidity =0.6.6;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import 'excalibur-core/contracts/interfaces/IExcaliburV2Factory.sol';
import 'excalibur-core/contracts/interfaces/IExcaliburV2Pair.sol';
import "./interfaces/IPriceConsumer.sol";
import './interfaces/IExcaliburRouter.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract ExcaliburRouter is IExcaliburRouter {
  using SafeMath for uint;

  IPriceConsumer priceConsumer;

  address public immutable EXC;
  address public immutable override factory;
  address public immutable override WETH;
  address public owner;

  // This address will be used to receive all the EXc that will be burn
  // when someone is paying 30% of the Fees in EXC
  // This is done to be able to do it without adding a custom burnFrom function into EXC
  address public immutable FEE_MANAGER;

  modifier ensure(uint deadline) {
    require(deadline >= block.timestamp, 'ExcaliburRouter: EXPIRED');
    _;
  }

  constructor(address _factory, address _WETH, address _EXC, address feeManager, IPriceConsumer _priceConsumer) public {
    factory = _factory;
    WETH = _WETH;

    priceConsumer = _priceConsumer;
    owner = msg.sender;
    EXC = _EXC;
    FEE_MANAGER = feeManager;
  }


  receive() external payable {
    assert(msg.sender == WETH);
    // only accept ETH via fallback from the WETH contract
  }

  function getPair(address token1, address token2) external view returns (address){
    return UniswapV2Library.pairFor(factory, token1, token2);
  }

  function isContract(address account) public view returns (bool){
    uint256 size;
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }

  // **** ADD LIQUIDITY ****
  function _addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin
  ) internal virtual returns (uint amountA, uint amountB) {
    // create the pair if it doesn't exist yet
    if (IExcaliburV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
      IExcaliburV2Factory(factory).createPair(tokenA, tokenB);
    }
    (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
    if (reserveA == 0 && reserveB == 0) {
      (amountA, amountB) = (amountADesired, amountBDesired);
    } else {
      uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
      if (amountBOptimal <= amountBDesired) {
        require(amountBOptimal >= amountBMin, 'ExcaliburRouter: INSUFFICIENT_B_AMOUNT');
        (amountA, amountB) = (amountADesired, amountBOptimal);
      } else {
        uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
        assert(amountAOptimal <= amountADesired);
        require(amountAOptimal >= amountAMin, 'ExcaliburRouter: INSUFFICIENT_A_AMOUNT');
        (amountA, amountB) = (amountAOptimal, amountBDesired);
      }
    }
  }

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
    (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
    address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
    TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
    TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
    liquidity = IExcaliburV2Pair(pair).mint(to);
  }

  function addLiquidityETH(
    address token,
    uint amountTokenDesired,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
    (amountToken, amountETH) = _addLiquidity(
      token,
      WETH,
      amountTokenDesired,
      msg.value,
      amountTokenMin,
      amountETHMin
    );
    address pair = UniswapV2Library.pairFor(factory, token, WETH);
    TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
    IWETH(WETH).deposit{value : amountETH}();
    assert(IWETH(WETH).transfer(pair, amountETH));
    liquidity = IExcaliburV2Pair(pair).mint(to);
    // refund dust eth, if any
    if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
  }

  // **** REMOVE LIQUIDITY ****
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
    address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
    IExcaliburV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
    // send liquidity to pair
    (uint amount0, uint amount1) = IExcaliburV2Pair(pair).burn(to);
    (address token0,) = UniswapV2Library.sortTokens(tokenA, tokenB);
    (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
    require(amountA >= amountAMin, 'ExcaliburRouter: INSUFFICIENT_A_AMOUNT');
    require(amountB >= amountBMin, 'ExcaliburRouter: INSUFFICIENT_B_AMOUNT');
  }

  function removeLiquidityETH(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
    (amountToken, amountETH) = removeLiquidity(
      token,
      WETH,
      liquidity,
      amountTokenMin,
      amountETHMin,
      address(this),
      deadline
    );
    TransferHelper.safeTransfer(token, to, amountToken);
    IWETH(WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityWithPermit(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external virtual override returns (uint amountA, uint amountB) {
    address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
    uint value = approveMax ? uint(- 1) : liquidity;
    IExcaliburV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
  }

  function removeLiquidityETHWithPermit(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external virtual override returns (uint amountToken, uint amountETH) {
    address pair = UniswapV2Library.pairFor(factory, token, WETH);
    uint value = approveMax ? uint(- 1) : liquidity;
    IExcaliburV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
  }

  // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
  function removeLiquidityETHSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) public virtual override ensure(deadline) returns (uint amountETH) {
    (, amountETH) = removeLiquidity(
      token,
      WETH,
      liquidity,
      amountTokenMin,
      amountETHMin,
      address(this),
      deadline
    );
    TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
    IWETH(WETH).withdraw(amountETH);
    TransferHelper.safeTransferETH(to, amountETH);
  }

  function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external virtual override returns (uint amountETH) {
    address pair = UniswapV2Library.pairFor(factory, token, WETH);
    uint value = approveMax ? uint(- 1) : liquidity;
    IExcaliburV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
    amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
      token, liquidity, amountTokenMin, amountETHMin, to, deadline
    );
  }

  // **** SWAP ****

  function getEXCFees(address swapToken, address toToken, uint swapTokenAmount) public view returns (uint estimatedExcAmount){
    if (swapToken == EXC) return 0;

    uint tokenPriceUSD = priceConsumer.valueOfTokenUSD(swapToken);
    address pair = IExcaliburV2Factory(factory).getPair(swapToken, toToken);

    if (tokenPriceUSD == 0 || pair == address(0)) return 0;

    uint feeAmount = IExcaliburV2Pair(pair).feeAmount();
    uint excPrice = priceConsumer.getEXCPriceUSD();

    uint swapTokenDecimals = IERC20(swapToken).decimals();
    if(swapTokenDecimals <= 18){
      swapTokenAmount = swapTokenAmount.mul(10**(18 - swapTokenDecimals));
    }
    else {
      swapTokenAmount = swapTokenAmount / (10**(swapTokenDecimals - 18));
    }

    uint feeAmountBUSD = swapTokenAmount.mul(tokenPriceUSD).mul(feeAmount) / 100000;
    uint excFeeAmountBUSD = feeAmountBUSD.mul(30) / 100;
    estimatedExcAmount = excFeeAmountBUSD / excPrice;

    return estimatedExcAmount;
  }

  function _payEXCFees(address account, address swapToken, address toToken, uint swapTokenAmount) internal {
    require(isContract(account), "ExcaliburRouter: contract not allowed");
    // Not allowed for contract
    uint excAmount = getEXCFees(swapToken, toToken, swapTokenAmount);
    require(excAmount > 0, "ExcaliburRouter: unable");
    TransferHelper.safeTransferFrom(EXC, msg.sender, FEE_MANAGER, excAmount);
  }

  // requires the initial amount to have already been sent to the first pair
  function _swap(uint[] memory amounts, address[] memory path, address _to, address referrer, bool hasPaidFeesInEXC) internal virtual {
    for (uint i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0,) = UniswapV2Library.sortTokens(input, output);
      uint amountOut = amounts[i + 1];
      (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
      address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;

      IExcaliburV2Pair pair = IExcaliburV2Pair(UniswapV2Library.pairFor(factory, input, output));
      if (referrer != address(0) || hasPaidFeesInEXC) {
        pair.swap2(amount0Out, amount1Out, to, referrer, hasPaidFeesInEXC);
      }
      else {
        pair.swap(amount0Out, amount1Out, to, new bytes(0));
      }
    }
  }

  function swapTokensForExactTokens(
    uint amountOut,
    uint amountInMax,
    address[] calldata path,
    address to,
    address referrer,
    bool payEXCFees,
    uint deadline
  ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
    amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path, payEXCFees);
    if (payEXCFees) {
      _payEXCFees(msg.sender, path[0], path[1], amounts[0]);
    }
    require(amounts[0] <= amountInMax, 'ExcaliburRouter: EXCESSIVE_INPUT_AMOUNT');
    TransferHelper.safeTransferFrom(
      path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
    );
    _swap(amounts, path, to, referrer, payEXCFees);
  }

  function swapTokensForExactETH(
    uint amountOut,
    uint amountInMax,
    address[] calldata path,
    address to,
    address referrer,
    bool payEXCFees,
    uint deadline
  )
  external
  virtual
  override
  ensure(deadline)
  returns (uint[] memory amounts)
  {
    require(path[path.length - 1] == WETH, 'ExcaliburRouter: INVALID_PATH');
    amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path, payEXCFees);
    require(amounts[0] <= amountInMax, 'ExcaliburRouter: EXCESSIVE_INPUT_AMOUNT');

    if (payEXCFees) {
      _payEXCFees(msg.sender, path[0], path[1], amounts[0]);
    }

    TransferHelper.safeTransferFrom(
      path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]
    );
    _swap(amounts, path, address(this), referrer, payEXCFees);
    IWETH(WETH).withdraw(amounts[amounts.length - 1]);
    TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
  }

  function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, address referrer,
    bool payEXCFees, uint deadline)
  external
  virtual
  override
  payable
  ensure(deadline)
  returns (uint[] memory amounts)
  {
    require(path[0] == WETH, 'ExcaliburRouter: INVALID_PATH');
    amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path, payEXCFees);
    require(amounts[0] <= msg.value, 'ExcaliburRouter: EXCESSIVE_INPUT_AMOUNT');
    if (payEXCFees) {
      _payEXCFees(msg.sender, path[0], path[1], amounts[0]);
    }
    IWETH(WETH).deposit{value : amounts[0]}();
    assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
    _swap(amounts, path, to, referrer, payEXCFees);
    // refund dust eth, if any
    if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
  }

  // **** SWAP (supporting fee-on-transfer tokens) ****
  // requires the initial amount to have already been sent to the first pair
  function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to, address referrer, bool hasPaidEXCFees) internal virtual {
    for (uint i; i < path.length - 1; i++) {
      (address input, address output) = (path[i], path[i + 1]);
      (address token0,) = UniswapV2Library.sortTokens(input, output);
      IExcaliburV2Pair pair = IExcaliburV2Pair(UniswapV2Library.pairFor(factory, input, output));
      uint amountOutput;
      {// scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        uint feeAmount = hasPaidEXCFees ? pair.feeAmount().mul(50) /100 : pair.feeAmount();
        amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput, feeAmount);
      }
      (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
      address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
      if(referrer != address(0) || hasPaidEXCFees){
        pair.swap2(amount0Out, amount1Out, to, referrer, hasPaidEXCFees);
      }
      else{
        pair.swap(amount0Out, amount1Out, to, new bytes(0));
      }
    }
  }

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    bool payEXCFees,
    uint deadline
  ) external virtual override ensure(deadline) {
    TransferHelper.safeTransferFrom(
      path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
    );
    if (payEXCFees) {
      _payEXCFees(msg.sender, path[0], path[1], amountIn);
    }
    uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to, referrer, payEXCFees);
    require(
      IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
      'ExcaliburRouter: INSUFFICIENT_OUTPUT_AMOUNT'
    );
  }

  function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    bool payEXCFees,
    uint deadline
  )
  external
  virtual
  override
  payable
  ensure(deadline)
  {
    require(path[0] == WETH, 'ExcaliburRouter: INVALID_PATH');
    uint amountIn = msg.value;
    IWETH(WETH).deposit{value : amountIn}();
    assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));

    if (payEXCFees) {
      _payEXCFees(msg.sender, path[0], path[1], amountIn);
    }

    uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
    _swapSupportingFeeOnTransferTokens(path, to, referrer, payEXCFees);
    require(
      IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
      'ExcaliburRouter: INSUFFICIENT_OUTPUT_AMOUNT'
    );
  }

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    bool payEXCFees,
    uint deadline
  )
  external
  virtual
  override
  ensure(deadline)
  {
    require(path[path.length - 1] == WETH, 'ExcaliburRouter: INVALID_PATH');
    TransferHelper.safeTransferFrom(
      path[0], msg.sender, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn
    );
    if (payEXCFees) {
      _payEXCFees(msg.sender, path[0], path[1], amountIn);
    }
    _swapSupportingFeeOnTransferTokens(path, address(this), referrer, payEXCFees);
    uint amountOut = IERC20(WETH).balanceOf(address(this));
    require(amountOut >= amountOutMin, 'ExcaliburRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    IWETH(WETH).withdraw(amountOut);
    TransferHelper.safeTransferETH(to, amountOut);
  }


  // **** LIBRARY FUNCTIONS ****
  function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
    return UniswapV2Library.quote(amountA, reserveA, reserveB);
  }

  function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut, uint feeAmount)
  public
  pure
  virtual
  override
  returns (uint amountOut)
  {
    return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut, feeAmount);
  }

  function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut, uint feeAmount)
  public
  pure
  virtual
  override
  returns (uint amountIn)
  {
    return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut, feeAmount);
  }

  function getAmountsOut(uint amountIn, address[] memory path, bool withReductionOnFee)
  public
  view
  virtual
  override
  returns (uint[] memory amounts)
  {
    return UniswapV2Library.getAmountsOut(factory, amountIn, path, withReductionOnFee);
  }

  function getAmountsIn(uint amountOut, address[] memory path, bool withReductionOnFee)
  public
  view
  virtual
  override
  returns (uint[] memory amounts)
  {
    return UniswapV2Library.getAmountsIn(factory, amountOut, path, withReductionOnFee);
  }
}
