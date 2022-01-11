const ExcaliburRouter = artifacts.require("ExcaliburRouter");
const PriceConsumer = artifacts.require("PriceConsumerV3");
const SwapFeeRebate = artifacts.require("SwapFeeRebate");

module.exports = async function (deployer, network, accounts) {
  let factoryAddress = process.env.FACTORY_ADDRESS.toString().trim();
  let excAddress = process.env.EXC_ADDRESS.toString().trim();
  let wethAddress = process.env.WETH_ADDRESS.toString().trim();

  if(network === 'avalancheLocal' || network === 'development'){
    factoryAddress = process.env.FACTORY_ADDRESS_TESTNET.toString().trim();
    excAddress = process.env.EXC_ADDRESS_TESTNET.toString().trim();
    wethAddress = process.env.WETH_ADDRESS_TESTNET.toString().trim();
  }

  let priceConsumerAddress = (await PriceConsumer.deployed()).address
  await deployer.deploy(SwapFeeRebate, factoryAddress, excAddress, priceConsumerAddress)
  let swapFeeRebateAddress = (await SwapFeeRebate.deployed()).address
  await deployer.deploy(ExcaliburRouter, factoryAddress, wethAddress, excAddress, swapFeeRebateAddress)
};
