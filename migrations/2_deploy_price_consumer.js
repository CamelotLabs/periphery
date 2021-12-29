const PriceConsumer = artifacts.require("PriceConsumerV3");

module.exports = async function (deployer, network, accounts) {
  let factoryAddress = process.env.FACTORY_ADDRESS.toString().trim();
  let excAddress = process.env.EXC_ADDRESS.toString().trim();
  let wethAddress = process.env.WETH_ADDRESS.toString().trim();
  let usdAddress = process.env.USD_ADDRESS.toString().trim();
  let usdDecimals = process.env.USD_DECIMALS.toString().trim();

  if(network === 'testnet' || network === 'development'){
    factoryAddress = process.env.FACTORY_ADDRESS_TESTNET.toString().trim();
    excAddress = process.env.EXC_ADDRESS_TESTNET.toString().trim();
    wethAddress = process.env.WETH_ADDRESS_TESTNET.toString().trim();
    usdAddress = process.env.USD_ADDRESS_TESTNET.toString().trim();
    usdDecimals = process.env.USD_DECIMALS_TESTNET.toString().trim();
  }



  await deployer.deploy(PriceConsumer, factoryAddress, wethAddress, usdAddress, excAddress, usdDecimals)
};
