pragma solidity ^0.6.0;

interface ISwapFeeRebate {
  function getEXCFees(address inputToken, address outputToken, uint outputTokenAmount) external returns (uint excAmount);
}