const CamelotRouter = artifacts.require("CamelotRouter");

module.exports = async function (deployer, network, accounts) {
  let factoryAddress = process.env.FACTORY_ADDRESS.toString().trim();
  let wethAddress = process.env.WETH_ADDRESS.toString().trim();

  if(network === 'arbitrum_testnet' || network === 'development'){
    factoryAddress = process.env.FACTORY_ADDRESS_TESTNET.toString().trim();
    wethAddress = process.env.WETH_ADDRESS_TESTNET.toString().trim();
  }
  await deployer.deploy(CamelotRouter, factoryAddress, wethAddress)
};
