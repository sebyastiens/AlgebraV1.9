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

interface IAlgebraPoolTables  {

    struct RangeDatas {
    int24 tick;
    uint256 MaxInjectable;
    uint256 MaxReceived;
    uint160 Price;
    uint128 InRangeLiquidity;
    }

    function setPool (address _algebraPoolAddress, address _dataStorageOperator, uint256 LoopLength) external returns (
      RangeDatas[] memory Max_Injectable_Token0,
      RangeDatas[] memory Max_Injectable_Token1
    );
  function GetMaxSwapTables(uint256 LoopLength)
    external
    //returns (
      //RangeDatas[] memory Max_Injectable_Token0,
     // RangeDatas[] memory Max_Injectable_Token1
   // )
returns (
      int24[] memory tick0,
    uint256[] memory maxInjectable0,
    uint256[] memory maxReceived0,
    uint160[] memory price0,
    uint128[] memory inRangeLiquidity0,
    int24[] memory tick1,
    uint256[] memory maxInjectable1,
    uint256[] memory maxReceived1,
    uint160[] memory price1,
    uint128[] memory inRangeLiquidity1
    )
;

}
