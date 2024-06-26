import "@nomicfoundation/hardhat-toolbox"
import "@nomiclabs/hardhat-truffle5"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-ethers"
import "hardhat-abi-exporter"
import 'hardhat-deploy'
import dotenv from 'dotenv'

dotenv.config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    arbitrumSepolia: {
      url: "https://sepolia-rollup.arbitrum.io/rpc",
      chainId: 421614,
      skipDryRun: true,
      accounts: [process.env.DEPLOYER_PKEY.toString().trim()],
    },
    arbitrumOne: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      skipDryRun: true,
      accounts: [process.env.DEPLOYER_PKEY.toString().trim()],
    },
    xai: {
      url: "https://xai-chain.net/rpc",
      chainId: 660279,
      skipDryRun: true,
      accounts: [process.env.DEPLOYER_PKEY.toString().trim()],
    }
  },
  solidity: {
    compilers: [{
      version: "0.6.6",
      settings: {
        optimizer: {
          enabled: true,
          runs: 99999
        }
      }
    }]
  },
  namedAccounts: {
    deployer: {
      default: 0,
      "arbitrumSepolia": process.env.DEPLOYER_ADDRESS.toString().trim(),
      "arbitrumOne": process.env.DEPLOYER_ADDRESS.toString().trim(),
      "xai": process.env.DEPLOYER_ADDRESS.toString().trim()
    }
  },
  etherscan: {
    apiKey: {
      "arbitrumSepolia": process.env.ARBISCAN_API_KEY.toString().trim(),
      "arbitrumOne": process.env.ARBISCAN_API_KEY.toString().trim(),
      "xai": process.env.ARBISCAN_API_KEY.toString().trim()
    },
    customChains: [{
      network: "arbitrumSepolia",
      chainId: 421614,
      urls: {
        apiURL: "https://api-sepolia.arbiscan.io/api",
        browserURL: "https://sepolia.arbiscan.io"
      }
    },{
      network: "xai",
      chainId: 660279,
      urls: {
        apiURL: "https://explorer.xai-chain.net/api",
        browserURL: "https://explorer.xai-chain.net/"
      }
    }]
  },
  abiExporter: {
    clear: true
  },

};
