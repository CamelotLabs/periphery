import chai, { expect } from 'chai'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { Contract } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'
import { AddressZero, MaxUint256 } from 'ethers/constants'
import IExcaliburV2Pair from 'excalibur-core/build/contracts/IExcaliburV2Pair.json'
import PriceFeeder from '../build/contracts/PriceFeeder.json'

import { v2Fixture } from './shared/fixtures'
import { expandTo18Decimals, getApprovalDigest, MINIMUM_LIQUIDITY } from './shared/utilities'

import DeflatingERC20 from '../build/contracts/DeflatingERC20.json'
import { ecsign } from 'ethereumjs-util'
import { BigNumberish } from 'ethers/utils/bignumber'

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
  let pair: Contract
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
    pair = fixture.pair
    priceConsumer = fixture.priceConsumer
    feeAmount = await fixture.pair.feeAmount()
  })

  it('getAmountOut with fee != 3%', async () => {
    expect(await router.getAmountOut(bigNumberify(2), bigNumberify(100), bigNumberify(100), 2000)).to.eq(
      bigNumberify(1)
    )
    expect(await router.getAmountOut(bigNumberify(100), bigNumberify(10000), bigNumberify(10000), 2000)).to.eq(
      bigNumberify(97)
    )
    expect(await router.getAmountOut(bigNumberify(100), bigNumberify(10000), bigNumberify(10000), 300)).to.eq(
      bigNumberify(98)
    )
  })

  it('getAmountIn with fee != 3%', async () => {
    expect(await router.getAmountIn(bigNumberify(1), bigNumberify(100), bigNumberify(100), 2000)).to.eq(
      bigNumberify(2)
    )
    expect(await router.getAmountIn(bigNumberify(97), bigNumberify(10000), bigNumberify(10000), 2000)).to.eq(
      bigNumberify(100)
    )
    expect(await router.getAmountIn(bigNumberify(98), bigNumberify(10000), bigNumberify(10000), 300)).to.eq(
      bigNumberify(100)
    )
  })

  it('getEXCFees', async () => {
    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(0)

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

    await token0.approve(router.address, MaxUint256)
    await token1.approve(router.address, MaxUint256)
    await router.addLiquidity(
      token0.address,
      token1.address,
      bigNumberify(10000),
      bigNumberify(10000),
      0,
      0,
      wallet.address,
      MaxUint256,
      overrides
    )

    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(0)

    var priceFeederToken1 = await deployContract(wallet, PriceFeeder, [0, 10], overrides)
    await priceConsumer.setTokenPriceFeeder(token1.address, USD.address, priceFeederToken1.address)

    // outputAmount * outputTokenPriceBUSD * feeAmount * feeRefundShare / excPrice
    await pair.setFeeAmount(300)
    // Tokens are not whitelisted
    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(0)
    await priceConsumer.setWhitelistToken(token0.address, true);
    await priceConsumer.setWhitelistToken(token1.address, true);
    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(expandTo18Decimals(15).div(10))
    await pair.setFeeAmount(600)
    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(expandTo18Decimals(3))

    await router.setFeeRefundShare(50)
    await pair.setFeeAmount(300)
    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(expandTo18Decimals(75).div(100))
    await pair.setFeeAmount(600)
    expect(await router.getEXCFees(token0.address, token1.address, expandTo18Decimals(100))).to.eq(expandTo18Decimals(15).div(10))
  })
})