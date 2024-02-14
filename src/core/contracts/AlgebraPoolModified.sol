// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IAlgebraPool.sol';
import './interfaces/IDataStorageOperator.sol';
import './interfaces/pool/IAlgebraPoolState.sol';

import './base/PoolState.sol';
import './base/PoolImmutables.sol';

import './libraries/PriceMovementMath.sol';
import './libraries/TickManager.sol';
import './libraries/TickTable.sol';

import './libraries/LowGasSafeMath.sol';
import './libraries/SafeCast.sol';

import './libraries/TickMath.sol';
import './libraries/LiquidityMath.sol';

import './interfaces/IERC20Minimal.sol';
import './interfaces/callback/IAlgebraSwapCallback.sol';

/// @title Algebra concentrated liquidity pool
/// @notice This contract is responsible for liquidity positions, swaps and flashloans
/// @dev Version: Algebra V1.9-directional-fee
contract AlgebraPool is PoolState, PoolImmutables, IAlgebraPool {
  using LowGasSafeMath for uint256;
  using LowGasSafeMath for int256;
  using LowGasSafeMath for uint128;
  using SafeCast for uint256;
  using SafeCast for int256;
  using TickTable for mapping(int16 => uint256);
  using TickManager for mapping(int24 => TickManager.Tick);

  function balanceToken0() private view returns (uint256) {
    return IERC20Minimal(token0).balanceOf(address(this));
  }

  function balanceToken1() private view returns (uint256) {
    return IERC20Minimal(token1).balanceOf(address(this));
  }

  /// @inheritdoc IAlgebraPoolState
  function timepoints(uint256 index)
    external
    view
    override
    returns (
      bool initialized,
      uint32 blockTimestamp,
      int56 tickCumulative,
      uint160 secondsPerLiquidityCumulative,
      uint88 volatilityCumulative,
      int24 averageTick,
      uint144 volumePerLiquidityCumulative
    )
  {
    return IDataStorageOperator(dataStorageOperator).timepoints(index);
  }

  /// @dev Updates fees according combinations of sigmoids
  function _updateFee(
    uint32 _time,
    int24 _tick,
    uint16 _index,
    uint128 _liquidity
  ) private returns (uint16 newFeeZto, uint16 newFeeOtz) {
    (newFeeZto, newFeeOtz) = IDataStorageOperator(dataStorageOperator).getFees(_time, _tick, _index, _liquidity);
    (globalState.feeZto, globalState.feeOtz) = (newFeeZto, newFeeOtz);
  }

  function _writeTimepoint(
    uint16 timepointIndex,
    uint32 blockTimestamp,
    int24 tick,
    uint128 liquidity,
    uint128 volumePerLiquidityInBlock
  ) private returns (uint16 newTimepointIndex) {
    return IDataStorageOperator(dataStorageOperator).write(timepointIndex, blockTimestamp, tick, liquidity, volumePerLiquidityInBlock);
  }

  function _getSingleTimepoint(
    uint32 blockTimestamp,
    uint32 secondsAgo,
    int24 startTick,
    uint16 timepointIndex,
    uint128 liquidityStart
  )
    private
    view
    returns (
      int56 tickCumulative,
      uint160 secondsPerLiquidityCumulative,
      uint112 volatilityCumulative,
      uint256 volumePerAvgLiquidity
    )
  {
    return IDataStorageOperator(dataStorageOperator).getSingleTimepoint(blockTimestamp, secondsAgo, startTick, timepointIndex, liquidityStart);
  }



  struct SwapCalculationCache {
    uint128 volumePerLiquidityInBlock;
    int56 tickCumulative; // The global tickCumulative at the moment
    uint160 secondsPerLiquidityCumulative; // The global secondPerLiquidity at the moment
    bool computedLatestTimepoint; //  if we have already fetched _tickCumulative_ and _secondPerLiquidity_ from the DataOperator
    int256 amountRequiredInitial; // The initial value of the exact input\output amount
    int256 amountCalculated; // The additive amount of total output\input calculated trough the swap
    uint16 fee; // The current dynamic fee when zeroToOne is true -> swapping token0 for token1
    int24 startTick; // The tick at the start of a swap
    uint16 timepointIndex; // The index of last written timepoint
  }

  struct PriceMovementCache {
    uint160 stepSqrtPrice; // The Q64.96 sqrt of the price at the start of the step
    int24 nextTick; // The tick till the current step goes
    bool initialized; // True if the _nextTick is initialized
    uint160 nextTickPrice; // The Q64.96 sqrt of the price calculated from the _nextTick
    uint256 input; // The additive amount of tokens that have been provided
    uint256 output; // The additive amount of token that have been withdrawn
    uint256 feeAmount; // The total amount of fee earned within a current step
  }

struct RangeDatas {
  int24 tick;
  uint256 MaxInjectable;
  uint256 MaxReceived;
  uint160 Price;
  uint128 InRangeLiquidity;
}

    function setPool (address _algebraPoolAddress, uint256 LoopLength) external returns (
      RangeDatas[] Max_Injectable_Token0,
      RangeDatas[] Max_Injectable_Token1
    ){
       (Max_Injectable_Token0 , Max_Injectable_Token1) = IAlgebraPoolState(_algebraPoolAddress).GetMaxSwapTables(LoopLength);
    }

  function GetMaxSwapTables(uint256 LoopLength)
    private
    returns (
      RangeDatas[] Max_Injectable_Token0,
      RangeDatas[] Max_Injectable_Token1
    )
  {

    uint32 blockTimestamp;
    SwapCalculationCache memory cache;
    RangeDatas memory currentRangeData;
    int24 currentLiquidity;
    bool Initialization_oTz = false ; // this will turn true after doing the initialization for oTz and used as the condition in the while loop to break the process
    {
      // load from one storage slot
      bool zeroToOne = true ;
      uint160 currentPrice = globalState.price;
      int24 currentTick = globalState.tick;
      cache.fee = globalState.feeZto;

      cache.timepointIndex = globalState.timepointIndex;
      (currentLiquidity, cache.volumePerLiquidityInBlock) = (liquidity, volumePerLiquidityInBlock); // liquidity comes from AlgebraPoolState
      cache.startTick = currentTick;

      blockTimestamp = _blockTimestamp();

      uint16 newTimepointIndex = _writeTimepoint(
        cache.timepointIndex,
        blockTimestamp,
        cache.startTick,
        currentLiquidity,
        cache.volumePerLiquidityInBlock
      );

      // new timepoint appears only for first swap in block
      if (newTimepointIndex != cache.timepointIndex) {
        cache.timepointIndex = newTimepointIndex;
        cache.volumePerLiquidityInBlock = 0;
        (cache.fee, ) = _updateFee(blockTimestamp, currentTick, newTimepointIndex, currentLiquidity);
      }
    }

    PriceMovementCache memory step;
    // swap until there is remaining input or output tokens or we reach the price limit
    uint256 i = 0 ;
    while (i<LoopLength) {
      step.stepSqrtPrice = currentPrice;
      (step.nextTick, step.initialized) = tickTable.nextTickInTheSameRow(currentTick, zeroToOne);
      step.nextTickPrice = TickMath.getSqrtRatioAtTick(step.nextTick);

      (currentPrice, step.input, step.output, step.feeAmount) = PriceMovementMath.movePriceTowardsTarget(
        zeroToOne,
        currentPrice,
        step.nextTickPrice,
        currentLiquidity,
        cache.fee
      );

        currentRangeData.tick = currentTick;
        currentRangeData.MaxInjectable = step.input + step.feeAmount;
        currentRangeData.MaxReceived = step.output; 
        currentRangeData.Price = step.nextTickPrice;
        currentRangeData.InRangeLiquidity = currentLiquidity;

           
        if (step.initialized) {
          // once at a swap we have to get the last timepoint of the observation
          if (!cache.computedLatestTimepoint) {
            (cache.tickCumulative, cache.secondsPerLiquidityCumulative, , ) = _getSingleTimepoint(
              blockTimestamp,
              0,
              cache.startTick,
              cache.timepointIndex,
              currentLiquidity // currentLiquidity can be changed only after computedLatestTimepoint
            );
            cache.computedLatestTimepoint = true;
          }
         
          int128 liquidityDelta;
          if (zeroToOne) {
            liquidityDelta = -ticks.cross(
              step.nextTick,
              0,
              0,
              cache.secondsPerLiquidityCumulative,
              cache.tickCumulative,
              blockTimestamp
            );
          } else {
            liquidityDelta = ticks.cross(
              step.nextTick,
              0,
              0,
              cache.secondsPerLiquidityCumulative,
              cache.tickCumulative,
              blockTimestamp
            );
          }

          currentLiquidity = LiquidityMath.addDelta(currentLiquidity, liquidityDelta);
        }

        currentTick = zeroToOne ? step.nextTick - 1 : step.nextTick;
        zeroToOne
        ? Max_Injectable_Token0.push(currentRangeData)
        : Max_Injectable_Token1.push(currentRangeData)
      // check stop condition
      if (i == LoopLength-1) {
        if (Initialization_oTz == true) {break;} // it means we are done
        // on prepare pour la loop a nouveau avec zeroToOne = false
        i = 0 ;
        cache = SwapCalculationCache(); // on les clean
        step = PriceMovementCache(); // on les clean
        zeroToOne = false;
        cache.fee = globalState.feeOtz;
        currentPrice = globalState.price;
        currentTick = globalState.tick;
        cache.timepointIndex = globalState.timepointIndex;
        (currentLiquidity, cache.volumePerLiquidityInBlock) = (liquidity, volumePerLiquidityInBlock); // liquidity comes from AlgebraPoolState
        cache.startTick = currentTick;

        blockTimestamp = _blockTimestamp();
  
        uint16 newTimepointIndex = _writeTimepoint(
          cache.timepointIndex,
          blockTimestamp,
          cache.startTick,
          currentLiquidity,
          cache.volumePerLiquidityInBlock
        );

        // new timepoint appears only for first swap in block
        if (newTimepointIndex != cache.timepointIndex) {
          cache.timepointIndex = newTimepointIndex;
          cache.volumePerLiquidityInBlock = 0;
          (, cache.fee) = _updateFee(blockTimestamp, currentTick, newTimepointIndex, currentLiquidity);
        }
        Initialization_oTz = true ;
      }
    }
  }
}
