import { Wallet, Contract } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import CamelotFactory from 'excalibur-core/build/contracts/CamelotFactory.json'
import Test from 'excalibur-core/build/contracts/Test.json'
import ICamelotPair from 'excalibur-core/build/contracts/ICamelotPair.json'

import ERC20 from '../../build/contracts/ERC20.json'
import WETH9 from '../../build/contracts/WETH9.json'
import CamelotRouter from '../../build/contracts/CamelotRouter.json'
import RouterEventEmitter from '../../build/contracts/RouterEventEmitter.json'
import {zeroAddress} from "ethereumjs-util";

const overrides = {
  gasLimit: 9999999
}

interface V2Fixture {
  token0: Contract
  token1: Contract
  WETH: Contract
  USD: Contract
  EXC: Contract
  WETHPartner: Contract
  factoryV2: Contract
  router02: Contract
  routerEventEmitter: Contract
  router: Contract
  pair: Contract
  WETHPair: Contract
}

export async function v2Fixture(provider: Web3Provider, [wallet]: Wallet[]): Promise<V2Fixture> {
  // deploy tokens
  const tokenA = await deployContract(wallet, ERC20, [expandTo18Decimals(100000)])
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(100000)])
  const EXC = await deployContract(wallet, ERC20, [expandTo18Decimals(100000)])
  const USD = await deployContract(wallet, ERC20, [expandTo18Decimals(100000)])
  const WETH = await deployContract(wallet, WETH9)
  const WETHPartner = await deployContract(wallet, ERC20, [expandTo18Decimals(10000)])

  // deploy V2
  const factoryV2 = await deployContract(wallet, CamelotFactory, [wallet.address], overrides)
  await factoryV2.setFeeTo(zeroAddress()); // match uniswap config
  await factoryV2.setOwnerFeeShare(16666); // match uniswap config

  // deploy router
  const router02 = await deployContract(wallet, CamelotRouter, [factoryV2.address, WETH.address], overrides)

  // event emitter for testing
  const routerEventEmitter = await deployContract(wallet, RouterEventEmitter, [])

  // initialize V2
  await factoryV2.createPair(tokenA.address, tokenB.address)
  const pairAddress = await factoryV2.getPair(tokenA.address, tokenB.address)
  const pair = new Contract(pairAddress, JSON.stringify(ICamelotPair.abi), provider).connect(wallet)
  await pair.setFeePercent(300, 300); // match uniswap config

  const token0Address = await pair.token0()
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  await factoryV2.createPair(WETH.address, WETHPartner.address)
  // console.log(await factoryV2.INIT_CODE_PAIR_HASH())
  const WETHPairAddress = await factoryV2.getPair(WETH.address, WETHPartner.address)
  const WETHPair = new Contract(WETHPairAddress, JSON.stringify(ICamelotPair.abi), provider).connect(wallet)
  return {
    token0,
    token1,
    WETH,
    USD,
    EXC,
    WETHPartner,
    factoryV2,
    router02,
    router: router02, // the default router, 01 had a minor bug
    routerEventEmitter,
    pair,
    WETHPair
  }
}
