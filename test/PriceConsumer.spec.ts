import chai, { expect } from 'chai'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { Contract } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'
import { AddressZero, MaxUint256 } from 'ethers/constants'
import IExcaliburV2Pair from 'excalibur-core/build_test/IExcaliburV2Pair.json'

import { v2Fixture } from './shared/fixtures'
import { expandTo18Decimals, getApprovalDigest, MINIMUM_LIQUIDITY } from './shared/utilities'

import PriceFeeder from '../build/PriceFeeder.json'
import { ecsign } from 'ethereumjs-util'
import { BigNumberish } from 'ethers/utils/bignumber'
import {describe} from "mocha";

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe('ExcaliburRouter', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token0: Contract
  let token1: Contract
  let USD: Contract
  let WETH: Contract
  let EXC: Contract
  let router: Contract
  let priceConsumer: Contract
  let feeAmount: BigNumberish
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)
    token0 = fixture.token0
    token1 = fixture.token1
    USD = fixture.USD
    WETH = fixture.WETH
    EXC = fixture.EXC
    router = fixture.router02
    priceConsumer = fixture.priceConsumer
    feeAmount = await fixture.pair.feeAmount()
  })

  describe('getEXCPriceUSD', () => {
    it('1$', async () => {
      await EXC.approve(router.address, MaxUint256)
      await USD.approve(router.address, MaxUint256)
      await router.addLiquidity(
        EXC.address,
        USD.address,
        bigNumberify(10000),
        bigNumberify(10000),
        0,
        0,
        wallet.address,
        MaxUint256,
        overrides
      )
      expect(await priceConsumer.getEXCPriceUSD()).to.eq(expandTo18Decimals(1))
      expect(await priceConsumer.valueOfTokenUSD(EXC.address)).to.eq(expandTo18Decimals(1))
    })

    it('2$', async () => {
      await EXC.approve(router.address, MaxUint256)
      await USD.approve(router.address, MaxUint256)
      await router.addLiquidity(
        EXC.address,
        USD.address,
        bigNumberify(5000),
        bigNumberify(10000),
        0,
        0,
        wallet.address,
        MaxUint256,
        overrides
      )
      expect(await priceConsumer.getEXCPriceUSD()).to.eq(expandTo18Decimals(2))
      expect(await priceConsumer.valueOfTokenUSD(EXC.address)).to.eq(expandTo18Decimals(2))
    })

    it('0.5$', async () => {
      await EXC.approve(router.address, MaxUint256)
      await USD.approve(router.address, MaxUint256)
      await router.addLiquidity(
        EXC.address,
        USD.address,
        bigNumberify(10000),
        bigNumberify(5000),
        0,
        0,
        wallet.address,
        MaxUint256,
        overrides
      )
      expect(await priceConsumer.getEXCPriceUSD()).to.eq(expandTo18Decimals(5).div(10))
      expect(await priceConsumer.valueOfTokenUSD(EXC.address)).to.eq(expandTo18Decimals(5).div(10))
    })
  })

  it('getTokenFairPriceUSD: priceFeeder USD', async () => {
    expect(await priceConsumer.getTokenFairPriceUSD(token0.address)).to.eq(expandTo18Decimals(0))
    expect(await priceConsumer.valueOfTokenUSD(token0.address)).to.eq(expandTo18Decimals(0))

    var priceFeederToken0 = await deployContract(wallet, PriceFeeder, [0, 1], overrides)
    await priceConsumer.addTokenPriceFeeder(token0.address, USD.address, priceFeederToken0.address)
    expect(await priceConsumer.getTokenFairPriceUSD(token0.address)).to.eq(expandTo18Decimals(1))
    expect(await priceConsumer.valueOfTokenUSD(token0.address)).to.eq(expandTo18Decimals(1))

    priceFeederToken0 = await deployContract(wallet, PriceFeeder, [20, expandTo18Decimals(100)], overrides)
    await priceConsumer.addTokenPriceFeeder(token0.address, USD.address, priceFeederToken0.address)
    expect(await priceConsumer.getTokenFairPriceUSD(token0.address)).to.eq(expandTo18Decimals(1))
    expect(await priceConsumer.valueOfTokenUSD(token0.address)).to.eq(expandTo18Decimals(1))
  })

  it('getTokenFairPriceUSD: priceFeeder WETH', async () => {
    expect(await priceConsumer.getTokenFairPriceUSD(token0.address)).to.eq(expandTo18Decimals(0))
    expect(await priceConsumer.valueOfTokenUSD(token0.address)).to.eq(expandTo18Decimals(0))

    const priceFeederWETH  = await deployContract(wallet, PriceFeeder, [0, 2], overrides) // 1WETH = 2USD
    await priceConsumer.addTokenPriceFeeder(WETH.address, USD.address, priceFeederWETH.address)

    var priceFeederToken0 = await deployContract(wallet, PriceFeeder, [0, 1], overrides)
    await priceConsumer.addTokenPriceFeeder(token0.address, WETH.address, priceFeederToken0.address)
    expect(await priceConsumer.getTokenFairPriceUSD(token0.address)).to.eq(expandTo18Decimals(2))
    expect(await priceConsumer.valueOfTokenUSD(token0.address)).to.eq(expandTo18Decimals(2))

    priceFeederToken0 = await deployContract(wallet, PriceFeeder, [20, expandTo18Decimals(100)], overrides)
    await priceConsumer.addTokenPriceFeeder(token0.address, WETH.address, priceFeederToken0.address)
    expect(await priceConsumer.getTokenFairPriceUSD(token0.address)).to.eq(expandTo18Decimals(2))
    expect(await priceConsumer.valueOfTokenUSD(token0.address)).to.eq(expandTo18Decimals(2))
  })
})