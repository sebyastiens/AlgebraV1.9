// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
pragma abicoder v2;

import './pool/IAlgebraPoolState.sol';
import './pool/IAlgebraPoolEvents.sol';
import './pool/IAlgebraPoolTables.sol';
import "../../libraries/TickTable.sol";

/**
 * @title The interface for a Algebra Pool
 * @dev The pool interface is broken up into many smaller pieces.
 * Credit to Uniswap Labs under GPL-2.0-or-later license:
 * https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
 */
interface IAlgebraPool is
  IAlgebraPoolState,
  IAlgebraPoolEvents,
  IAlgebraPoolTables,
TickTable
{
  // used only for combining interfaces
}
