#!/usr/bin/env bash
# Reproduces every number in results/summary.md.
# Requirements: Foundry (CI pins v1.7.1) and Python 3. forge downloads solc 0.8.38 and 0.8.39 itself.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p results
RAW=results/raw.txt
: > "$RAW"

forge --version | sed -n 1p | tee -a "$RAW"

for version in 0.8.38 0.8.39; do
  for mode in "legacy" "legacy + optimizer" "via-IR" "via-IR + optimizer"; do
    flags=()
    [[ $mode == via-IR* ]] && flags+=(--via-ir)
    [[ $mode == *optimizer ]] && flags+=(--optimize)
    echo "===== solc $version | $mode =====" | tee -a "$RAW"

    if ! log=$(forge test --use "$version" "${flags[@]}" --force -vv 2>&1); then
      echo "$log"
      exit 1
    fi
    grep -E '^\s+[A-Z] ' <<< "$log" >> "$RAW"

    # Record the settings solc actually used, from the artifact metadata.
    python3 - >> "$RAW" <<'PY'
import json
m = json.load(open("out/Corruption.t.sol/ArrayFirstTest.json"))["metadata"]
s = m["settings"]
o = s["optimizer"]
print(f"  build: {m['compiler']['version']} | evm {s['evmVersion']} | viaIR {s.get('viaIR', False)} | optimizer {o['enabled']} runs {o['runs']}")
PY

    # Every failing depth attempt must end in an EVM stack overflow, not in out-of-gas.
    trace=$(forge test --use "$version" "${flags[@]}" --mt test_K_depthScan -vvvv 2>&1)
    echo "  K trace: StackOverflow failures $(grep -c '\[StackOverflow\]' <<< "$trace" || true)" >> "$RAW"
    echo "  K trace: other failures $(grep -oE '← \[[A-Za-z]+\]' <<< "$trace" | grep -vcE '\[(Stop|Return|StackOverflow)\]' || true)" >> "$RAW"
  done
done

python3 script/analyze.py "$RAW" results/summary.md
