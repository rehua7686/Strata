#!/bin/bash
# after queue2: a third pass of A (setup config, AP-Q4_K_XL)
S=<SCRIPTS>; C=<BENCH>/configs; B=<BENCH>
until grep -q '^exit=' $B/pass3-C2-docs-handbuilt-ap-q4_k_xl/bench-console.txt 2>/dev/null; do sleep 5; done
sleep 8   # let the previous server shut down
$S/chain.sh pass3-A-setup-ap-q4_k_xl:$C/setup-ap-q4_k_xl.json
