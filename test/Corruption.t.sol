// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Log} from "./Log.sol";

/// @notice Targeted reproductions. Each log line states the correct value as "(expect N)".
/// Layout: the recursive array is declared before the value field.
contract ArrayFirstTest {
    struct Node {
        Node[] children;
        uint256 data;
    }

    Node root;
    Node[] roots;
    mapping(uint256 => Node) nodes;

    /// A: the example from the Solidity write-up.
    function test_A_direct() external {
        root.children.push();
        root.children[0].data = 1;

        root = root.children[0];

        Log.u("A direct: root.data (expect 1)", root.data);
    }

    /// B: the same overlap, reached through a storage pointer parameter and a mapping key.
    function test_B_alias() external {
        nodes[7].children.push();
        nodes[7].children[0].data = 1;

        _copyInto7(nodes[7].children[0]);

        Log.u("B alias: nodes[7].data (expect 1)", nodes[7].data);
    }

    function _copyInto7(Node storage src) internal {
        nodes[7] = src;
    }

    /// C: array-to-array form.
    function test_C_array() external {
        roots.push();
        roots[0].children.push();
        roots[0].children.push();
        roots[0].children[0].data = 11;
        roots[0].children[1].data = 12;

        roots = roots[0].children;

        Log.u("C array: roots.length (expect 2)", roots.length);
        Log.u("C array: roots[0].data (expect 11)", roots.length > 0 ? roots[0].data : 0);
        Log.u("C array: roots[1].data (expect 12)", roots.length > 1 ? roots[1].data : 0);
    }
}

/// Layout: the value field is declared before the recursive array.
contract DataFirstTest {
    struct Node {
        uint256 data;
        Node[] children;
    }

    Node root;

    /// D: root{100} -> child{1} -> [{2}, {3}]; copy root = root.children[0].
    function test_D_dataFirst() external {
        root.data = 100;
        root.children.push();
        Node storage child = root.children[0];
        child.data = 1;
        child.children.push();
        child.children.push();
        child.children[0].data = 2;
        child.children[1].data = 3;

        root = root.children[0];

        Log.u("D data-first: root.data (expect 1)", root.data);
        Log.u("D data-first: root.children.length (expect 2)", root.children.length);
        Log.u("D data-first: children[0].data (expect 2)", root.children.length > 0 ? root.children[0].data : 0);
        Log.u("D data-first: children[1].data (expect 3)", root.children.length > 1 ? root.children[1].data : 0);
    }
}

/// G/H: a shallow assertion passes on the affected compiler; a deep comparison does not.
contract SpineTest {
    struct Node {
        uint256 data;
        Node[] children;
    }

    Node root;

    /// root{100}
    /// └─ S{1}              source: root.children[0]
    ///    ├─ A{2}
    ///    │  ├─ {4}
    ///    │  └─ {5}
    ///    └─ B{3}
    ///       └─ {6}
    function _build() internal {
        root.data = 100;
        root.children.push();
        Node storage s = root.children[0];
        s.data = 1;
        s.children.push();
        s.children.push();
        s.children[0].data = 2;
        s.children[0].children.push();
        s.children[0].children.push();
        s.children[0].children[0].data = 4;
        s.children[0].children[1].data = 5;
        s.children[1].data = 3;
        s.children[1].children.push();
        s.children[1].children[0].data = 6;
    }

    function _dump(Node storage n, string memory path) internal view {
        Log.u(string.concat("G ", path, ".data"), n.data);
        Log.u(string.concat("G ", path, ".children.length"), n.children.length);
        for (uint256 i; i < n.children.length; ++i) {
            _dump(n.children[i], string.concat(path, i == 0 ? ".c0" : ".c1"));
        }
    }

    function _equal(Node storage a, Node memory b) internal view returns (bool) {
        if (a.data != b.data || a.children.length != b.children.length) return false;
        for (uint256 i; i < b.children.length; ++i) {
            if (!_equal(a.children[i], b.children[i])) return false;
        }
        return true;
    }

    /// G: full dump after the copy. Correct result: 1 -> [2 -> [4, 5], 3 -> [6]].
    function test_G_spine() external {
        _build();
        root = root.children[0];
        _dump(root, "root");
    }

    /// H: the storage-to-memory snapshot is not affected by the bug, so it serves as the oracle.
    function test_H_deepCompare() external {
        _build();
        Node memory expected = root.children[0];

        root = root.children[0];

        bool shallow = root.data == 1 && root.children.length == 2 && root.children[0].data == 2;
        Log.u("H shallow check passes (top value, top length, first child value)", shallow ? 1 : 0);
        Log.u("H deep compare against memory snapshot passes", _equal(root, expected) ? 1 : 0);
    }
}
