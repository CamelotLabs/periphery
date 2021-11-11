pragma solidity ^0.6.0;

interface IPriceConsumer {
  function USD() external pure returns (address);
  function WETH() external pure returns (address);
  function EXC() external pure returns (address);
  function isWhitelistedToken(address token) external view returns (bool isWhitelisted);
  function valueOfToTokenUSD(address fromToken, address toToken) external view returns(uint valueInUSD);
  function valueOfTokenUSD(address token) external view returns (uint valueInUSD);
  function getTokenFairPriceUSD(address token) external view returns (uint);
  function getWETHFairPriceUSD() external view returns (uint);
  function getEXCPriceUSD() external view returns (uint);
}
