pragma solidity ^0.6.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

/**
* This is a fake contract use in unit test to simulate chainlink's price feeder
*/
contract PriceFeeder is AggregatorV3Interface {
  uint8 public override decimals;
  int256 price;

  constructor(uint8 decimals_, int256 price_) public {
    decimals = decimals_;
    price = price_;
  }

  function description() external view virtual override returns (string memory){
    return "TEST";
  }

  function version() external view virtual override returns (uint256){
    return 1;
  }

  function getRoundData(uint80 _roundId) external view virtual override returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ){
    return (0,0,0,0,0);
  }

  function latestRoundData() external view virtual override returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    ){
    return (0,price,0,0,0);
  }
}