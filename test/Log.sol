// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/// @notice Minimal console logger without forge-std: calls Foundry's console address directly.
library Log {
    address internal constant CONSOLE = 0x000000000000000000636F6e736F6c652e6c6f67;

    function u(string memory key, uint256 value) internal view {
        _send(abi.encodeWithSignature("log(string,uint256)", key, value));
    }

    function uu(string memory key, uint256 a, uint256 b) internal view {
        _send(abi.encodeWithSignature("log(string,uint256,uint256)", key, a, b));
    }

    function _send(bytes memory payload) private view {
        (bool ok,) = CONSOLE.staticcall(payload);
        ok;
    }
}
