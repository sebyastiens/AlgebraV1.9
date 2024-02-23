// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;
import './DataStorage.sol';

library SafeConvert {
    function uintToString(uint _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
    function boolToString(bool _b) internal pure returns (string memory) {
        return _b ? "true" : "false";
    }
    function intToString(int _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        bool negative = _i < 0;
        uint len;
        uint j;
        if (negative) {
            // If _i is negative, make it positive to work with it
            j = uint(-_i);
        } else {
            j = uint(_i);
        }

        // Determine the length of the number
        uint i = j;
        while (i != 0) {
            len++;
            i /= 10;
        }

        if (negative) {
            // Increase length for the negative sign
            len++;
        }

        bytes memory bstr = new bytes(len);
        uint k = len;
        while (j != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(j - j / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            j /= 10;
        }

        if (negative) {
            // Add the negative sign at the beginning
            bstr[0] = '-';
        }

        return string(bstr);
    }

    function timepointToString(DataStorage.Timepoint memory _timepoint) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "index: ", uintToString(_timepoint.index),
            ", initialized: ", boolToString(_timepoint.initialized),
            ", blockTimestamp: ", uintToString(_timepoint.blockTimestamp),
            ", tickCumulative: ", intToString(_timepoint.tickCumulative),
            ", secondsPerLiquidityCumulative: ", uintToString(_timepoint.secondsPerLiquidityCumulative),
            ", volatilityCumulative: ", uintToString(_timepoint.volatilityCumulative),
            ", averageTick: ", intToString(_timepoint.averageTick),
            ", volumePerLiquidityCumulative: ", uintToString(_timepoint.volumePerLiquidityCumulative)
        ));
    }
}
