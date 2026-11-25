// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Log} from "./Log.sol";

// Deterministic random differential test (Z).
//
// For each copy: build a random tree in storage, snapshot the source into memory, perform the
// overlapping storage-to-storage copy, then compare the result with the snapshot field by field.
// Storage-to-memory copies are not affected by the bug, so the snapshot is the oracle; on 0.8.39
// the comparison must find no difference at all.
//
// Generator (keccak256 chain, seed fixed per contract and copy form):
//   - top level: 1-3 nodes, uniform; each gets a subtree of depth 1-4, uniform
//   - every node above the depth limit has 0-3 children, uniform
//   - every value field gets a unique non-zero value (global counter), so any wrong value is visible
//   - the source index k is uniform over the top-level nodes
// Forms:
//   struct: trees[t] = trees[t].children[k]
//   array:  lists[t] = lists[t][k].children
// Field classes (a field is a value or an array length):
//   zeroed        exists in the result, reads 0, expected non-zero
//   nonZeroWrong  exists in the result, reads a different non-zero value
//   dropped       belongs to a node missing from the result (an array came back shorter)
//   extra         belongs to a node that should not exist in the result
//
// The three contracts below are identical except for the order of fields in Node.

contract FuzzArrayFirstTest {
    struct Node {
        Node[] children;
        uint256 b;
    }

    struct Stats {
        uint256 corrupted;
        uint256 expectedFields;
        uint256 zeroed;
        uint256 nonZeroWrong;
        uint256 dropped;
        uint256 extra;
        uint256 sourceNodes;
        uint256 maxSourceNodes;
    }

    uint256 private constant COPIES = 1000;
    uint256 private constant FIELDS_PER_NODE = 2;

    mapping(uint256 => Node) private trees;
    mapping(uint256 => Node[]) private lists;
    uint256 private counter;
    uint256 private seed;
    Stats private s;

    function _rand(uint256 n) internal returns (uint256) {
        seed = uint256(keccak256(abi.encode(seed)));
        return seed % n;
    }

    function _build(Node storage n, uint256 depth) internal {
        n.b = ++counter;
        if (depth == 0) return;
        uint256 w = _rand(4);
        for (uint256 i; i < w; ++i) {
            n.children.push();
            _build(n.children[i], depth - 1);
        }
    }

    function _nodes(Node memory e) internal pure returns (uint256 c) {
        c = 1;
        for (uint256 i; i < e.children.length; ++i) c += _nodes(e.children[i]);
    }

    function _nodesS(Node storage a) internal view returns (uint256 c) {
        c = 1;
        for (uint256 i; i < a.children.length; ++i) c += _nodesS(a.children[i]);
    }

    function _field(uint256 actual, uint256 expected) internal {
        if (actual == expected) return;
        if (actual == 0) ++s.zeroed;
        else ++s.nonZeroWrong;
    }

    function _cmp(Node storage a, Node memory e) internal {
        _field(a.b, e.b);
        _field(a.children.length, e.children.length);
        _cmpList(a.children, e.children);
    }

    function _cmpList(Node[] storage a, Node[] memory e) internal {
        uint256 n = a.length < e.length ? a.length : e.length;
        for (uint256 i; i < n; ++i) _cmp(a[i], e[i]);
        for (uint256 i = n; i < e.length; ++i) s.dropped += FIELDS_PER_NODE * _nodes(e[i]);
        for (uint256 i = n; i < a.length; ++i) s.extra += FIELDS_PER_NODE * _nodesS(a[i]);
    }

    function _errors() internal view returns (uint256) {
        return s.zeroed + s.nonZeroWrong + s.dropped + s.extra;
    }

    function _account(uint256 nodeCount) internal {
        s.sourceNodes += nodeCount;
        s.expectedFields += FIELDS_PER_NODE * nodeCount;
        if (nodeCount > s.maxSourceNodes) s.maxSourceNodes = nodeCount;
    }

    function _report(string memory form) internal view {
        string memory p = string.concat("Z ArrayFirst ", form, " ");
        Log.u(string.concat(p, "copies"), COPIES);
        Log.u(string.concat(p, "corrupted"), s.corrupted);
        Log.u(string.concat(p, "expectedFields"), s.expectedFields);
        Log.u(string.concat(p, "zeroed"), s.zeroed);
        Log.u(string.concat(p, "nonZeroWrong"), s.nonZeroWrong);
        Log.u(string.concat(p, "dropped"), s.dropped);
        Log.u(string.concat(p, "extra"), s.extra);
        Log.u(string.concat(p, "sourceNodes"), s.sourceNodes);
        Log.u(string.concat(p, "maxSourceNodes"), s.maxSourceNodes);
    }

    function test_Z_struct() external {
        seed = uint256(keccak256(abi.encode("solc-0.8.39-repro", "ArrayFirst", "struct")));
        for (uint256 t; t < COPIES; ++t) {
            Node storage r = trees[t];
            uint256 w = 1 + _rand(3);
            for (uint256 i; i < w; ++i) {
                r.children.push();
                _build(r.children[i], 1 + _rand(4));
            }
            uint256 k = _rand(w);
            Node memory expected = r.children[k];
            _account(_nodes(expected));
            uint256 before = _errors();

            trees[t] = trees[t].children[k];

            _cmp(trees[t], expected);
            if (_errors() != before) ++s.corrupted;
        }
        _report("struct");
    }

    function test_Z_array() external {
        seed = uint256(keccak256(abi.encode("solc-0.8.39-repro", "ArrayFirst", "array")));
        for (uint256 t; t < COPIES; ++t) {
            Node[] storage l = lists[t];
            uint256 w = 1 + _rand(3);
            for (uint256 i; i < w; ++i) {
                l.push();
                _build(l[i], 1 + _rand(4));
            }
            uint256 k = _rand(w);
            Node[] memory expected = l[k].children;
            uint256 nodeCount;
            for (uint256 i; i < expected.length; ++i) nodeCount += _nodes(expected[i]);
            _account(nodeCount);
            uint256 before = _errors();

            lists[t] = lists[t][k].children;

            _cmpList(lists[t], expected);
            if (_errors() != before) ++s.corrupted;
        }
        _report("array");
    }
}

contract FuzzDataFirstTest {
    struct Node {
        uint256 a;
        Node[] children;
    }

    struct Stats {
        uint256 corrupted;
        uint256 expectedFields;
        uint256 zeroed;
        uint256 nonZeroWrong;
        uint256 dropped;
        uint256 extra;
        uint256 sourceNodes;
        uint256 maxSourceNodes;
    }

    uint256 private constant COPIES = 1000;
    uint256 private constant FIELDS_PER_NODE = 2;

    mapping(uint256 => Node) private trees;
    mapping(uint256 => Node[]) private lists;
    uint256 private counter;
    uint256 private seed;
    Stats private s;

    function _rand(uint256 n) internal returns (uint256) {
        seed = uint256(keccak256(abi.encode(seed)));
        return seed % n;
    }

    function _build(Node storage n, uint256 depth) internal {
        n.a = ++counter;
        if (depth == 0) return;
        uint256 w = _rand(4);
        for (uint256 i; i < w; ++i) {
            n.children.push();
            _build(n.children[i], depth - 1);
        }
    }

    function _nodes(Node memory e) internal pure returns (uint256 c) {
        c = 1;
        for (uint256 i; i < e.children.length; ++i) c += _nodes(e.children[i]);
    }

    function _nodesS(Node storage a) internal view returns (uint256 c) {
        c = 1;
        for (uint256 i; i < a.children.length; ++i) c += _nodesS(a.children[i]);
    }

    function _field(uint256 actual, uint256 expected) internal {
        if (actual == expected) return;
        if (actual == 0) ++s.zeroed;
        else ++s.nonZeroWrong;
    }

    function _cmp(Node storage a, Node memory e) internal {
        _field(a.a, e.a);
        _field(a.children.length, e.children.length);
        _cmpList(a.children, e.children);
    }

    function _cmpList(Node[] storage a, Node[] memory e) internal {
        uint256 n = a.length < e.length ? a.length : e.length;
        for (uint256 i; i < n; ++i) _cmp(a[i], e[i]);
        for (uint256 i = n; i < e.length; ++i) s.dropped += FIELDS_PER_NODE * _nodes(e[i]);
        for (uint256 i = n; i < a.length; ++i) s.extra += FIELDS_PER_NODE * _nodesS(a[i]);
    }

    function _errors() internal view returns (uint256) {
        return s.zeroed + s.nonZeroWrong + s.dropped + s.extra;
    }

    function _account(uint256 nodeCount) internal {
        s.sourceNodes += nodeCount;
        s.expectedFields += FIELDS_PER_NODE * nodeCount;
        if (nodeCount > s.maxSourceNodes) s.maxSourceNodes = nodeCount;
    }

    function _report(string memory form) internal view {
        string memory p = string.concat("Z DataFirst ", form, " ");
        Log.u(string.concat(p, "copies"), COPIES);
        Log.u(string.concat(p, "corrupted"), s.corrupted);
        Log.u(string.concat(p, "expectedFields"), s.expectedFields);
        Log.u(string.concat(p, "zeroed"), s.zeroed);
        Log.u(string.concat(p, "nonZeroWrong"), s.nonZeroWrong);
        Log.u(string.concat(p, "dropped"), s.dropped);
        Log.u(string.concat(p, "extra"), s.extra);
        Log.u(string.concat(p, "sourceNodes"), s.sourceNodes);
        Log.u(string.concat(p, "maxSourceNodes"), s.maxSourceNodes);
    }

    function test_Z_struct() external {
        seed = uint256(keccak256(abi.encode("solc-0.8.39-repro", "DataFirst", "struct")));
        for (uint256 t; t < COPIES; ++t) {
            Node storage r = trees[t];
            uint256 w = 1 + _rand(3);
            for (uint256 i; i < w; ++i) {
                r.children.push();
                _build(r.children[i], 1 + _rand(4));
            }
            uint256 k = _rand(w);
            Node memory expected = r.children[k];
            _account(_nodes(expected));
            uint256 before = _errors();

            trees[t] = trees[t].children[k];

            _cmp(trees[t], expected);
            if (_errors() != before) ++s.corrupted;
        }
        _report("struct");
    }

    function test_Z_array() external {
        seed = uint256(keccak256(abi.encode("solc-0.8.39-repro", "DataFirst", "array")));
        for (uint256 t; t < COPIES; ++t) {
            Node[] storage l = lists[t];
            uint256 w = 1 + _rand(3);
            for (uint256 i; i < w; ++i) {
                l.push();
                _build(l[i], 1 + _rand(4));
            }
            uint256 k = _rand(w);
            Node[] memory expected = l[k].children;
            uint256 nodeCount;
            for (uint256 i; i < expected.length; ++i) nodeCount += _nodes(expected[i]);
            _account(nodeCount);
            uint256 before = _errors();

            lists[t] = lists[t][k].children;

            _cmpList(lists[t], expected);
            if (_errors() != before) ++s.corrupted;
        }
        _report("array");
    }
}

contract FuzzSandwichTest {
    struct Node {
        uint256 a;
        Node[] children;
        uint256 b;
    }

    struct Stats {
        uint256 corrupted;
        uint256 expectedFields;
        uint256 zeroed;
        uint256 nonZeroWrong;
        uint256 dropped;
        uint256 extra;
        uint256 sourceNodes;
        uint256 maxSourceNodes;
    }

    uint256 private constant COPIES = 1000;
    uint256 private constant FIELDS_PER_NODE = 3;

    mapping(uint256 => Node) private trees;
    mapping(uint256 => Node[]) private lists;
    uint256 private counter;
    uint256 private seed;
    Stats private s;

    function _rand(uint256 n) internal returns (uint256) {
        seed = uint256(keccak256(abi.encode(seed)));
        return seed % n;
    }

    function _build(Node storage n, uint256 depth) internal {
        n.a = ++counter;
        n.b = ++counter;
        if (depth == 0) return;
        uint256 w = _rand(4);
        for (uint256 i; i < w; ++i) {
            n.children.push();
            _build(n.children[i], depth - 1);
        }
    }

    function _nodes(Node memory e) internal pure returns (uint256 c) {
        c = 1;
        for (uint256 i; i < e.children.length; ++i) c += _nodes(e.children[i]);
    }

    function _nodesS(Node storage a) internal view returns (uint256 c) {
        c = 1;
        for (uint256 i; i < a.children.length; ++i) c += _nodesS(a.children[i]);
    }

    function _field(uint256 actual, uint256 expected) internal {
        if (actual == expected) return;
        if (actual == 0) ++s.zeroed;
        else ++s.nonZeroWrong;
    }

    function _cmp(Node storage a, Node memory e) internal {
        _field(a.a, e.a);
        _field(a.b, e.b);
        _field(a.children.length, e.children.length);
        _cmpList(a.children, e.children);
    }

    function _cmpList(Node[] storage a, Node[] memory e) internal {
        uint256 n = a.length < e.length ? a.length : e.length;
        for (uint256 i; i < n; ++i) _cmp(a[i], e[i]);
        for (uint256 i = n; i < e.length; ++i) s.dropped += FIELDS_PER_NODE * _nodes(e[i]);
        for (uint256 i = n; i < a.length; ++i) s.extra += FIELDS_PER_NODE * _nodesS(a[i]);
    }

    function _errors() internal view returns (uint256) {
        return s.zeroed + s.nonZeroWrong + s.dropped + s.extra;
    }

    function _account(uint256 nodeCount) internal {
        s.sourceNodes += nodeCount;
        s.expectedFields += FIELDS_PER_NODE * nodeCount;
        if (nodeCount > s.maxSourceNodes) s.maxSourceNodes = nodeCount;
    }

    function _report(string memory form) internal view {
        string memory p = string.concat("Z Sandwich ", form, " ");
        Log.u(string.concat(p, "copies"), COPIES);
        Log.u(string.concat(p, "corrupted"), s.corrupted);
        Log.u(string.concat(p, "expectedFields"), s.expectedFields);
        Log.u(string.concat(p, "zeroed"), s.zeroed);
        Log.u(string.concat(p, "nonZeroWrong"), s.nonZeroWrong);
        Log.u(string.concat(p, "dropped"), s.dropped);
        Log.u(string.concat(p, "extra"), s.extra);
        Log.u(string.concat(p, "sourceNodes"), s.sourceNodes);
        Log.u(string.concat(p, "maxSourceNodes"), s.maxSourceNodes);
    }

    function test_Z_struct() external {
        seed = uint256(keccak256(abi.encode("solc-0.8.39-repro", "Sandwich", "struct")));
        for (uint256 t; t < COPIES; ++t) {
            Node storage r = trees[t];
            uint256 w = 1 + _rand(3);
            for (uint256 i; i < w; ++i) {
                r.children.push();
                _build(r.children[i], 1 + _rand(4));
            }
            uint256 k = _rand(w);
            Node memory expected = r.children[k];
            _account(_nodes(expected));
            uint256 before = _errors();

            trees[t] = trees[t].children[k];

            _cmp(trees[t], expected);
            if (_errors() != before) ++s.corrupted;
        }
        _report("struct");
    }

    function test_Z_array() external {
        seed = uint256(keccak256(abi.encode("solc-0.8.39-repro", "Sandwich", "array")));
        for (uint256 t; t < COPIES; ++t) {
            Node[] storage l = lists[t];
            uint256 w = 1 + _rand(3);
            for (uint256 i; i < w; ++i) {
                l.push();
                _build(l[i], 1 + _rand(4));
            }
            uint256 k = _rand(w);
            Node[] memory expected = l[k].children;
            uint256 nodeCount;
            for (uint256 i; i < expected.length; ++i) nodeCount += _nodes(expected[i]);
            _account(nodeCount);
            uint256 before = _errors();

            lists[t] = lists[t][k].children;

            _cmpList(lists[t], expected);
            if (_errors() != before) ++s.corrupted;
        }
        _report("array");
    }
}
