// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Log} from "./Log.sol";

interface IVm {
    function cool(address target) external;
}

/// @notice Gas of a non-overlapping storage-to-storage copy onto targets of growing size.
/// Target: N leaf nodes (N = 0, 10, ..., 100). Source: a separate node with one leaf child.
/// Measured with gasleft() around the assignment: execution gas, before refunds.
contract GasTest {
    IVm private constant VM = IVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Node {
        Node[] children;
        uint256 data;
    }

    mapping(uint256 => Node) nodes;

    function _fill(Node storage n, uint256 width) internal {
        for (uint256 i; i < width; ++i) {
            n.children.push();
            n.children[i].data = i + 1;
        }
    }

    function _measure(uint256 id, uint256 targetWidth, bool cold) internal returns (uint256 used) {
        Node storage dst = nodes[id];
        Node storage src = nodes[id + 1_000_000];
        _fill(dst, targetWidth);
        _fill(src, 1);
        if (cold) VM.cool(address(this)); // marks every storage slot of this contract cold

        uint256 g = gasleft();
        nodes[id] = src;
        used = g - gasleft();

        require(nodes[id].children.length == 1 && nodes[id].children[0].data == 1, "bad copy");
    }

    /// E: storage written earlier in the same transaction (warm).
    function test_E_warmGas() external {
        for (uint256 n; n <= 100; n += 10) {
            Log.uu("E warm gas: nested structs in target", n, _measure(1 + n, n, false));
        }
    }

    /// J: identical copies with all slots marked cold first.
    function test_J_coldGas() external {
        for (uint256 n; n <= 100; n += 10) {
            Log.uu("J cold gas: nested structs in target", n, _measure(1 + n, n, true));
        }
    }
}

/// @notice Deepest target the copy can overwrite before the transaction fails.
/// Target: a linear chain of depth d (every node has exactly one child). Source: an empty node.
/// The copy does not overlap. Success means the external call returns without reverting.
contract DepthTest {
    struct Node {
        Node[] children;
        uint256 data;
    }

    mapping(uint256 => Node) nodes;

    function attempt(uint256 id, uint256 depth) external {
        Node storage cur = nodes[id];
        for (uint256 i; i < depth; ++i) {
            cur.children.push();
            cur = cur.children[0];
        }
        nodes[id] = nodes[id + 1_000_000];
    }

    /// K: linear scan d = 1..260. run.sh checks the trace: every failure must be a StackOverflow.
    function test_K_depthScan() external {
        uint256 lastOk;
        uint256 firstFail;
        uint256 okAfterFail;
        uint256 failures;
        for (uint256 d = 1; d <= 260; ++d) {
            try this.attempt{gas: 200_000_000}(d, d) {
                lastOk = d;
                if (firstFail != 0) ++okAfterFail;
            } catch {
                ++failures;
                if (firstFail == 0) firstFail = d;
            }
        }
        Log.u("K scan: last successful depth", lastOk);
        Log.u("K scan: first failing depth", firstFail);
        Log.u("K scan: failures", failures);
        Log.u("K scan: successes after first failure", okAfterFail);
    }
}
