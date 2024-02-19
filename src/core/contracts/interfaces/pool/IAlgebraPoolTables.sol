// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
pragma abicoder v2;


/**
 * @title Pool state that is not stored
 * @notice Contains view functions to provide information about the pool that is computed rather than stored on the
 * blockchain. The functions here may have variable gas costs.
 * @dev Credit to Uniswap Labs under GPL-2.0-or-later license:
 * https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
 */
import "../../libraries/DataStorage.sol";
import "../../libraries/Constants.sol";


interface IAlgebraPoolTables  {

    struct RangeDatas {
    int24 tick;
    uint256 MaxInjectable;
    uint256 MaxReceived;
    uint160 Price;
    uint128 InRangeLiquidity;
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

  struct StateValuesCache {
    uint160 currentPrice;
    int24 currentTick;
    uint128 currentLiquidity;
}

    function setPool (address _algebraPoolAddress, uint256 LoopLength) external returns (
      RangeDatas[] memory Max_Injectable_Token0,
      RangeDatas[] memory Max_Injectable_Token1
    );


  function GetMaxSwapTables(uint256 index,address algebraPoolAddress,bool zeroForOne,SwapCalculationCache memory cache,PriceMovementCache memory step,StateValuesCache memory CurrentState,DataStorage.Timepoint[UINT16_MODULO] memory  timepointsMemory)
    external view 
    returns (
      RangeDatas memory,
      SwapCalculationCache memory,
      PriceMovementCache memory,
      StateValuesCache memory,
      DataStorage.Timepoint[UINT16_MODULO] memory
    )

;

}
