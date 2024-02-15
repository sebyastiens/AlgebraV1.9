// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import '../TickManager.sol';

library TickCrossView {

function getliquidityDelta(
    mapping(int24 => Tick) storage self,
    int24 tick
  ) internal returns (int128 liquidityDelta) {
    Tick storage data = self[tick];
    return data.liquidityDelta;
  }
