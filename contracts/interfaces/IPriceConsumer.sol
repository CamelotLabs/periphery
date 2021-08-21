pragma solidity ^0.6.0;

interface IPriceConsumer {
  function USD() external pure returns (address);
  function WETH() external pure returns (address);
  function EXC() external pure returns (address);
  function getTokenFairPriceUSD(address token) external view returns (uint);
  function getWETHFairPriceUSD() external view returns (uint);
  function getEXCPriceUSD() external view returns (uint);
  function valueOfTokenUSD(address token) external view returns (uint valueInUSD);
}
