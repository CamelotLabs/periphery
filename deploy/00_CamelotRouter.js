const hre = require("hardhat");
require('dotenv').config();

module.exports = async ({getNamedAccounts, deployments}) => {
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();

  let factoryAddress = process.env.FACTORY_ADDRESS.toString().trim();
  let wethAddress = process.env.WETH_ADDRESS.toString().trim();

  // Deploy Factory
  await deploy('CamelotRouter', {
    from: deployer,
    args: [factoryAddress, wethAddress],
    log: true,
  });
};
module.exports.tags = ['CamelotRouter'];