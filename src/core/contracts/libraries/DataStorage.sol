// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './FullMath.sol';
import '../interfaces/IAlgebraPool.sol';
import './SafeConvert.sol';

/// @title DataStorage
/// @notice Provides price, liquidity, volatility data useful for a wide variety of system designs
/// @dev Instances of stored dataStorage data, "timepoints", are collected in the dataStorage array
/// Timepoints are overwritten when the full length of the dataStorage array is populated.
/// The most recent timepoint is available by passing 0 to getSingleTimepoint()


library DataStorage {
  uint32 public constant WINDOW = 1 days;
  uint256 private constant UINT16_MODULO = 65536;
  uint256 internal constant ReducedArraySize = 15;

  struct Timepoint {
    uint16 index ; // Actual timePointIndex
    bool initialized; // whether or not the timepoint is initialized
    uint32 blockTimestamp; // the block timestamp of the timepoint
    int56 tickCumulative; // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
    uint160 secondsPerLiquidityCumulative; // the seconds per liquidity since the pool was first initialized
    uint88 volatilityCumulative; // the volatility accumulator; overflow after ~34800 years is desired :)
    int24 averageTick; // average tick at this blockTimestamp
    uint144 volumePerLiquidityCumulative; // the gmean(volumes)/liquidity accumulator
  }

  struct functionCallStruct {
    address poolAddress;
    uint16 index;
    uint32 time;
    int24 tick;
    uint128 liquidity;
    uint128 volumePerLiquidity;
  }

  struct binarySearchStruct {
    address poolAddress;
    uint32 time;
    uint32 target;
    uint16 lastIndex;
    uint16 oldestIndex;
}

  /// @notice Calculates volatility between two sequential timepoints with resampling to 1 sec frequency
  /// @param dt Timedelta between timepoints, must be within uint32 range
  /// @param tick0 The tick at the left timepoint, must be within int24 range
  /// @param tick1 The tick at the right timepoint, must be within int24 range
  /// @param avgTick0 The average tick at the left timepoint, must be within int24 range
  /// @param avgTick1 The average tick at the right timepoint, must be within int24 range
  /// @return volatility The volatility between two sequential timepoints
  /// If the requirements for the parameters are met, it always fits 88 bits
  function _volatilityOnRange(
    int256 dt,
    int256 tick0,
    int256 tick1,
    int256 avgTick0,
    int256 avgTick1
  ) internal pure returns (uint256 volatility) {
    // On the time interval from the previous timepoint to the current
    // we can represent tick and average tick change as two straight lines:
    // tick = k*t + b, where k and b are some constants
    // avgTick = p*t + q, where p and q are some constants
    // we want to get sum of (tick(t) - avgTick(t))^2 for every t in the interval (0; dt]
    // so: (tick(t) - avgTick(t))^2 = ((k*t + b) - (p*t + q))^2 = (k-p)^2 * t^2 + 2(k-p)(b-q)t + (b-q)^2
    // since everything except t is a constant, we need to use progressions for t and t^2:
    // sum(t) for t from 1 to dt = dt*(dt + 1)/2 = sumOfSequence
    // sum(t^2) for t from 1 to dt = dt*(dt+1)*(2dt + 1)/6 = sumOfSquares
    // so result will be: (k-p)^2 * sumOfSquares + 2(k-p)(b-q)*sumOfSequence + dt*(b-q)^2
    int256 K = (tick1 - tick0) - (avgTick1 - avgTick0); // (k - p)*dt
    int256 B = (tick0 - avgTick0) * dt; // (b - q)*dt
    int256 sumOfSquares = (dt * (dt + 1) * (2 * dt + 1)); // sumOfSquares * 6
    int256 sumOfSequence = (dt * (dt + 1)); // sumOfSequence * 2
    volatility = uint256((K**2 * sumOfSquares + 6 * B * K * sumOfSequence + 6 * dt * B**2) / (6 * dt**2));
  }

  /// @notice Transforms a previous timepoint into a new timepoint, given the passage of time and the current tick and liquidity values
  /// @dev blockTimestamp _must_ be chronologically equal to or greater than last.blockTimestamp, safe for 0 or 1 overflows
  /// @param last The specified timepoint to be used in creation of new timepoint
  /// @param prevTick The active tick at the time of the last timepoint
  /// @param averageTick The average tick at the time of the new timepoint
  /// @param temp the struct with all required params
  /// @return Timepoint The newly populated timepoint
  function createNewTimepointWithIndex(
    uint16 index, //added
    Timepoint memory last,
    int24 prevTick,
    int24 averageTick,
    functionCallStruct memory temp
  ) private pure returns (Timepoint memory) {

    Timepoint memory newTimepoint = Timepoint({
        index: index,
        initialized: true,
        blockTimestamp: temp.time,
        tickCumulative: last.tickCumulative + int56(temp.tick) * (temp.time - last.blockTimestamp),
        secondsPerLiquidityCumulative: last.secondsPerLiquidityCumulative + ((uint160(temp.time - last.blockTimestamp) << 128) / (temp.liquidity > 0 ? temp.liquidity : 1)),
        volatilityCumulative: last.volatilityCumulative + uint88(_volatilityOnRange(temp.time - last.blockTimestamp, prevTick, temp.tick, last.averageTick, averageTick)),
        averageTick: averageTick,
        volumePerLiquidityCumulative: last.volumePerLiquidityCumulative + temp.volumePerLiquidity
    });
    return newTimepoint;
  }

function createNewTimepoint(
    Timepoint memory last,
    int24 prevTick,
    int24 averageTick,
    functionCallStruct memory temp
  ) private pure returns (Timepoint memory) {
    uint32 delta = temp.time - last.blockTimestamp;
    last.initialized = true;
    last.blockTimestamp = temp.time;
    last.tickCumulative += int56(temp.tick) * delta;
    last.secondsPerLiquidityCumulative += ((uint160(delta) << 128) / (temp.liquidity > 0 ? temp.liquidity : 1)); // just timedelta if temp.liquidity == 0
    last.volatilityCumulative += uint88(_volatilityOnRange(delta, prevTick, temp.tick, last.averageTick, averageTick)); // always fits 88 bits
    last.averageTick = averageTick;
    last.volumePerLiquidityCumulative += temp.volumePerLiquidity;

    return last;
  }

  /// @notice comparator for 32-bit timestamps
  /// @dev safe for 0 or 1 overflows, a and b _must_ be chronologically before or equal to currentTime
  /// @param a A comparison timestamp from which to determine the relative position of `currentTime`
  /// @param b From which to determine the relative position of `currentTime`
  /// @param currentTime A timestamp truncated to 32 bits
  /// @return res Whether `a` is chronologically <= `b`
  function lteConsideringOverflow(
    uint32 a,
    uint32 b,
    uint32 currentTime
  ) private pure returns (bool res) {
    res = a > currentTime;
    if (res == b > currentTime) res = a <= b; // if both are on the same side
  }

  /// @dev guaranteed that the result is within the bounds of int24
  /// returns int256 for fuzzy tests
  function _getAverageTick(
    Timepoint[ReducedArraySize] memory self, //avant storage
    uint16 oldestIndex,
    uint32 lastTimestamp,
    int56 lastTickCumulative,
    functionCallStruct memory temp
  ) internal view returns (int256 avgTick,Timepoint[ReducedArraySize] memory) {
    uint256 ArrayIndex = getArrayIndex(self,oldestIndex);
    if(!self[ArrayIndex].initialized){
      self[ArrayIndex] = UpdateSelf(temp.poolAddress,oldestIndex);
    }
    uint32 oldestTimestamp = self[ArrayIndex].blockTimestamp;
    int56 oldestTickCumulative =self[ArrayIndex].tickCumulative;

    if (lteConsideringOverflow(oldestTimestamp, temp.time - WINDOW, temp.time)) {
      if (lteConsideringOverflow(lastTimestamp, temp.time - WINDOW, temp.time)) {
        temp.index -= 1; // considering underflow
        ArrayIndex = getArrayIndex(self,temp.index);
        if(!self[ArrayIndex].initialized){
          self[ArrayIndex] = UpdateSelf(temp.poolAddress,temp.index);
        }
        avgTick = self[ArrayIndex].initialized
          ? (lastTickCumulative - self[ArrayIndex].tickCumulative) / (lastTimestamp - self[ArrayIndex].blockTimestamp)
          : temp.tick;
      } else {
        Timepoint memory startOfWindow;
        require(temp.liquidity == 0,"Erreur : temp.liquidity n'est pas 0, donc il faut adapter le code car on doit passer 0 comme liquidity a ce stade");
        (startOfWindow, self) = getSingleTimepoint(self, WINDOW, oldestIndex, temp);

        //    current-WINDOW  last   current
        // _________*____________*_______*_
        //           ||||||||||||
        avgTick = (lastTickCumulative - startOfWindow.tickCumulative) / (lastTimestamp - temp.time + WINDOW);
      }
    } else {
      avgTick = (lastTimestamp == oldestTimestamp) ? temp.tick : (lastTickCumulative - oldestTickCumulative) / (lastTimestamp - oldestTimestamp);
    }
    return (avgTick,self);
  }

  /// @notice Fetches the timepoints beforeOrAt and atOrAfter a target, i.e. where [beforeOrAt, atOrAfter] is satisfied.
  /// The result may be the same timepoint, or adjacent timepoints.
  /// @dev The answer must be contained in the array, used when the target is located within the stored timepoint
  /// boundaries: older than the most recent timepoint and younger, or the same age as, the oldest timepoint
  /// @param self The memorized dataStorage array
  /// @param param The struct
  /// @return beforeOrAt The timepoint recorded before, or at, the target
  /// @return atOrAfter The timepoint recorded at, or after, the target
  function binarySearch(
    Timepoint[ReducedArraySize] memory self,
    binarySearchStruct  memory param

    // address poolAddress, // IAlgebraPool(poolAddress).timepoints() The accessible stored data
    // uint32 time, //time The current block.timestamp
    // uint32 target,//The timestamp at which the reserved timepoint should be for
    // uint16 lastIndex, //The index of the timepoint that was most recently written to the timepoints array
    // uint16 oldestIndex // The index of the oldest timepoint in the timepoints array
  ) private view returns (Timepoint memory beforeOrAt, Timepoint memory atOrAfter) {
    uint256 left = param.oldestIndex; // oldest timepoint
    uint256 right = param.lastIndex >= param.oldestIndex ? param.lastIndex : param.lastIndex + UINT16_MODULO; // newest timepoint considering one index overflow
    uint256 current = (left + right) >> 1; // "middle" point between the boundaries
    uint256 ArrayIndex;
    do {
      ArrayIndex = getArrayIndex(self,uint16(current));
      if(!self[ArrayIndex].initialized){
        self[ArrayIndex] = UpdateSelf(param.poolAddress,uint16(current));
      }
      beforeOrAt = self[ArrayIndex]; // checking the "middle" point between the boundaries
      (bool initializedBefore, uint32 timestampBefore) = (beforeOrAt.initialized, beforeOrAt.blockTimestamp);
      if (initializedBefore) {
        if (lteConsideringOverflow(timestampBefore, param.target, param.time)) {
          // is current point before or at `target`?
          ArrayIndex = getArrayIndex(self,uint16(current+1));
          if(!self[ArrayIndex].initialized){
            self[ArrayIndex] = UpdateSelf(param.poolAddress,uint16(current+1));
          }
          atOrAfter = self[ArrayIndex]; // checking the next point after "middle"
          (bool initializedAfter, uint32 timestampAfter) = (atOrAfter.initialized, atOrAfter.blockTimestamp);
          if (initializedAfter) {
            if (lteConsideringOverflow(param.target, timestampAfter, param.time)) {
              // is the "next" point after or at `target`?
              return (beforeOrAt, atOrAfter); // the only fully correct way to finish
            }
            left = current + 1; // "next" point is before the `target`, so looking in the right half
          } else {
            // beforeOrAt is initialized and <= target, and next timepoint is uninitialized
            // should be impossible if initial boundaries and `target` are correct
            return (beforeOrAt, beforeOrAt);
          }
        } else {
          right = current - 1; // current point is after the `target`, so looking in the left half
        }
      } else {
        // we've landed on an uninitialized timepoint, keep searching higher
        // should be impossible if initial boundaries and `target` are correct
        left = current + 1;
      }
      current = (left + right) >> 1; // calculating the new "middle" point index after updating the bounds
    } while (true);

    atOrAfter = beforeOrAt; // code is unreachable, to suppress compiler warning
    assert(false);
  }

  /// @dev Reverts if an timepoint at or before the desired timepoint timestamp does not exist.
  /// 0 may be passed as `secondsAgo' to return the current cumulative values.
  /// If called with a timestamp falling between two timepoints, returns the counterfactual accumulator values
  /// at exactly the timestamp between the two timepoints.
  /// @param self The memorized dataStorage array
  /// @param secondsAgo The amount of time to look back, in seconds, at which point to return an timepoint
  /// @param oldestIndex The index of the oldest timepoint
  /// @param temp the struct with all required params
  /// @return targetTimepoint desired timepoint or it's approximation
  function getSingleTimepoint(
    Timepoint[ReducedArraySize] memory self, //avant storage
    uint32 secondsAgo,
    uint16 oldestIndex,
    functionCallStruct memory temp

  ) internal view returns (Timepoint memory targetTimepoint,Timepoint[ReducedArraySize] memory) {
    uint32 target = temp.time - secondsAgo;

    // if target is newer than last timepoint
    uint256 ArrayIndex = getArrayIndex(self,temp.index);
    if(!self[ArrayIndex].initialized){
      self[ArrayIndex] = UpdateSelf(temp.poolAddress,temp.index);
    }
    if (secondsAgo == 0 || lteConsideringOverflow(self[ArrayIndex].blockTimestamp, target, temp.time)) {
      Timepoint memory last = self[ArrayIndex];

      
      if (last.blockTimestamp == target) {
        return (last,self);
      } else {
        // otherwise, we need to add new timepoint


        (int256 rawAvgTick, Timepoint[ReducedArraySize] memory updatedSelf) = _getAverageTick(self, oldestIndex, last.blockTimestamp, last.tickCumulative,temp);
        //int24 avgTick = int24(rawAvgTick);
        self = updatedSelf; 
        int24 prevTick = temp.tick;
        {
          if (temp.index != oldestIndex) {
            Timepoint memory prevLast;
            ArrayIndex = getArrayIndex(self,temp.index-1);
            if(!self[ArrayIndex].initialized){
              self[ArrayIndex] = UpdateSelf(temp.poolAddress,temp.index-1);
            }
            
            prevLast.blockTimestamp = self[ArrayIndex].blockTimestamp;
            prevLast.tickCumulative = self[ArrayIndex].tickCumulative;
            prevTick = int24((last.tickCumulative - prevLast.tickCumulative) / (last.blockTimestamp - prevLast.blockTimestamp));
          }
        } 
        return (createNewTimepoint(last, prevTick, int24(rawAvgTick), temp),self);
      }
    }
    ArrayIndex = getArrayIndex(self,oldestIndex);
    if(!self[ArrayIndex].initialized){
      self[ArrayIndex] = UpdateSelf(temp.poolAddress,oldestIndex);
    }
    require(lteConsideringOverflow(self[ArrayIndex].blockTimestamp, target, temp.time), 'OLD');
    binarySearchStruct memory searchParams = binarySearchStruct({
    poolAddress: temp.poolAddress,
    time: temp.time, 
    target: target, 
    lastIndex: temp.index, 
    oldestIndex: oldestIndex
});
    //(Timepoint memory beforeOrAt, Timepoint memory atOrAfter) = binarySearch(self,temp.poolAddress, temp.time, target, temp.index, oldestIndex);
    (Timepoint memory beforeOrAt, Timepoint memory atOrAfter) = binarySearch(
      self,
      searchParams
    );

    if (target == atOrAfter.blockTimestamp) {
      return (atOrAfter,self); // we're at the right boundary
    }

    if (target != beforeOrAt.blockTimestamp) {
      // we're in the middle
      uint32 timepointTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
      uint32 targetDelta = target - beforeOrAt.blockTimestamp;

      // For gas savings the resulting point is written to beforeAt
      beforeOrAt.tickCumulative += ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / timepointTimeDelta) * targetDelta;
      beforeOrAt.secondsPerLiquidityCumulative += uint160(
        (uint256(atOrAfter.secondsPerLiquidityCumulative - beforeOrAt.secondsPerLiquidityCumulative) * targetDelta) / timepointTimeDelta
      );
      beforeOrAt.volatilityCumulative += ((atOrAfter.volatilityCumulative - beforeOrAt.volatilityCumulative) / timepointTimeDelta) * targetDelta;
      beforeOrAt.volumePerLiquidityCumulative +=
        ((atOrAfter.volumePerLiquidityCumulative - beforeOrAt.volumePerLiquidityCumulative) / timepointTimeDelta) *
        targetDelta;
    }

    // we're at the left boundary or at the middle
    return (beforeOrAt,self);
  }

  /// @notice Returns average volatility in the range from time-WINDOW to time
  /// @param self The memorized dataStorage array
  /// @param temp the struct with all required params
  /// @return volatilityAverage The average volatility in the recent range
  /// @return volumePerLiqAverage The average volume per liquidity in the recent range
  function getAverages(
    Timepoint[ReducedArraySize] memory self, //avant storage
    functionCallStruct memory temp
  ) internal view returns (uint88 volatilityAverage, uint256 volumePerLiqAverage,Timepoint[ReducedArraySize] memory) {
    uint16 oldestIndex;
    if(!self[0].initialized){
      self[0] = UpdateSelf(temp.poolAddress,0);
    }
    Timepoint memory oldest = self[0];
    uint16 nextIndex = temp.index + 1; // considering overflow
    uint256 ArrayIndex = getArrayIndex(self,nextIndex);
    if(!self[ArrayIndex].initialized){
      self[ArrayIndex] = UpdateSelf(temp.poolAddress,nextIndex);
    }
    // condition if inutile vu qu'on vient de l'initialisé à la ligne du dessus

    //if ( self[ArrayIndex].initialized) {
      oldest = self[ArrayIndex];
      oldestIndex = nextIndex;
    //}
    
    Timepoint memory endOfWindow;
     (endOfWindow, self)= getSingleTimepoint(self, 0, oldestIndex, temp);

    uint32 oldestTimestamp = oldest.blockTimestamp;
    if (lteConsideringOverflow(oldestTimestamp, temp.time - WINDOW, temp.time)) {
      Timepoint memory startOfWindow;
    (startOfWindow, self) = getSingleTimepoint(self, WINDOW, oldestIndex, temp);
      return (
        (endOfWindow.volatilityCumulative - startOfWindow.volatilityCumulative) / WINDOW,
        uint256(endOfWindow.volumePerLiquidityCumulative - startOfWindow.volumePerLiquidityCumulative) >> 57,
        self
      );
    } else if (temp.time != oldestTimestamp) {
      uint88 _oldestVolatilityCumulative = oldest.volatilityCumulative;
      uint144 _oldestVolumePerLiquidityCumulative = oldest.volumePerLiquidityCumulative;
      return (
        (endOfWindow.volatilityCumulative - _oldestVolatilityCumulative) / (temp.time - oldestTimestamp),
        uint256(endOfWindow.volumePerLiquidityCumulative - _oldestVolumePerLiquidityCumulative) >> 57,
        self
      );
    }
  }

  

  /// @notice Writes an dataStorage timepoint to the array
  /// @dev Writable at most once per block. Index represents the most recently written element. index must be tracked externally.
  /// @param self The memorized dataStorage array
  /// @param temp the struct with all required params
  /// @return indexUpdated The new index of the most recently written element in the dataStorage array
  function write(
    Timepoint[ReducedArraySize] memory self, //avant storage
    functionCallStruct memory temp
  ) internal view returns (uint16 indexUpdated,Timepoint[ReducedArraySize] memory) {
    //if(!self[5].initialized){ // inutil car self est toujours vide à ce stade du code
      self[5] = UpdateSelf(temp.poolAddress,temp.index);
    //}

    // JE COMMENTE CA CAR ON FAIT UN SEUL CALL DE CETTE FONCTION ET DONC CETTE CONDITION NE SERA JAMAIS VERIFIEE...+ CA JOUERAIT PAS LA CAR CA PASSERAIT DANS LE IF
    //// early return if we've already written an timepoint this block
    if (self[5].blockTimestamp == temp.time) {
     return (temp.index,self);
    }
    //Timepoint memory last = self[5]; remove 1 local variable

    // get next index considering overflow
    indexUpdated = temp.index + 1;

    uint16 oldestIndex;
    // check if we have overflow in the past 
    Timepoint memory updatedTimepoint = UpdateSelf(temp.poolAddress, indexUpdated);
    if(updatedTimepoint.initialized){
        oldestIndex = indexUpdated;
        self[getArrayIndex(self, indexUpdated)] = updatedTimepoint;
    }
    // condition if inutile vu qu'on vient de l'initialisé à la ligne du dessus -> 23/02/24 : FAUX ON DOIT PAS INITIALISER indexUpdated avant de checker .initialized. DONC ON DOIT VOIR SI IL L'EST DEJA VIA L'INTERFACE

    (int256 rawAvgTick, Timepoint[ReducedArraySize] memory updatedSelf) = _getAverageTick(self,oldestIndex, temp.time, self[5].tickCumulative,temp); // le temp,index peut être modifié de -1 parfois dedans
    int24 avgTick = int24(rawAvgTick);
    self = updatedSelf; 
    int24 prevTick = temp.tick;
    if (temp.index != oldestIndex) {
      if(!self[getArrayIndex(self,temp.index - 1)].initialized){
        self[getArrayIndex(self,temp.index - 1)] = UpdateSelf(temp.poolAddress,temp.index - 1);
      }
      //uint32 _prevLastBlockTimestamp = self[getArrayIndex(self,temp.index - 1)].blockTimestamp; // considering index underflow
      //int56 _prevLastTickCumulative = self[getArrayIndex(self,temp.index - 1)].tickCumulative;
      prevTick = int24((self[5].tickCumulative -  self[getArrayIndex(self,temp.index - 1)].tickCumulative) / (self[5].blockTimestamp - self[getArrayIndex(self,temp.index - 1)].blockTimestamp));
    }
    self[getArrayIndex(self,indexUpdated)] = createNewTimepointWithIndex(indexUpdated,self[5], prevTick, avgTick, temp);
    return (indexUpdated,self);
  }

  function UpdateSelf(address poolAddress, uint16 index) internal view returns (Timepoint memory timepoint){
    // COMMENTé POUR EVITER LES SOUCIS AVEC timepoints. SI ON VEUT LA REUTILIER IL FAUT Ré-AJOUTER timepoints dans IAlgebraPoolState    
//(bool initialized, uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulative, uint88 volatilityCumulative, int24 averageTick, uint144 volumePerLiquidityCumulative) = IAlgebraPool(poolAddress).timepoints(index);
    //timepoint.index = index;
    //timepoint.initialized = initialized;
    //timepoint.blockTimestamp = blockTimestamp;
    //timepoint.tickCumulative = tickCumulative;
    //timepoint.secondsPerLiquidityCumulative = secondsPerLiquidityCumulative;
    //timepoint.volatilityCumulative = volatilityCumulative;
    //timepoint.averageTick = averageTick;
    //timepoint.volumePerLiquidityCumulative = volumePerLiquidityCumulative;    
  }

function getArrayIndex(Timepoint[ReducedArraySize] memory timepoints, uint16 index) internal pure returns (uint256 Arrayindex) { // Arrayindex could be uint8 but not sure it costs less
    //if (index == 0) { Arrayindex = 0;}
    //else {
      uint16 StartingIndex = timepoints[5].index; // timePointIndex of the cache.timePointIndex  = globalState.timePointIndex = temp.index
      int16 IndexDifference =  int16(index) - int16(StartingIndex); // la différence
      require(IndexDifference >= -2 && IndexDifference <= 4, "IndexDifference out of bounds");
      Arrayindex = uint256(5 + IndexDifference);
    //}
}


}
