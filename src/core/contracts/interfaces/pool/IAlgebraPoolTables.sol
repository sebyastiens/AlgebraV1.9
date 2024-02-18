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

    struct GlobalStateStructure{
      uint160 price;
      int24 tick;
      uint16 feeZto;
      uint16 feeOtz;
      uint16 timepointIndex;
      uint8 communityFeeToken0;
      uint8 communityFeeToken1;
      bool unlocked;
  }

    //function setPool (address _algebraPoolAddress, uint256 LoopLength) external returns (
     // RangeDatas[] memory Max_Injectable_Token0,
     // RangeDatas[] memory Max_Injectable_Token1
   // );


  function GetMaxSwapTables(uint256 LoopLength,address algebraPoolAddress)
    external view
    returns (
      RangeDatas[] memory Max_Injectable_Token0,
      RangeDatas[] memory Max_Injectable_Token1
    )

;

}
