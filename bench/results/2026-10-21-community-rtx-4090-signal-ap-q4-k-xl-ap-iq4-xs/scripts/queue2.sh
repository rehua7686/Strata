#!/bin/bash
# waits for the running 100-token A/B to finish, then runs the rest of the plan back to back
S=<SCRIPTS>; C=<BENCH>/configs; B=<BENCH>
until grep -q '^exit=' $B/ab-adapt-max100/ab-console.txt 2>/dev/null; do sleep 5; done
echo "== ab-adapt-max512 $(date -Is)"
$S/ab_run.sh ab-adapt-max512 512 4 $C/docs-handbuilt.json default: "adapt:xargs=--adapt-every;1;--adapt-swaps;80;--adapt-decay;0.97" || exit 2
$S/chain.sh kv-1-int8:$C/docs-handbuilt.json kv-1-q4_0:$C/docs-handbuilt-kvq4_0.json \
            kv-2-int8:$C/docs-handbuilt.json kv-2-q4_0:$C/docs-handbuilt-kvq4_0.json \
            pass3-B-setup-ap-iq4_xs:$C/setup-ap-iq4_xs.json \
            pass3-C-docs-handbuilt-ap-q4_k_xl:$C/docs-handbuilt.json \
            pass3-C2-docs-handbuilt-ap-q4_k_xl:$C/docs-handbuilt.json
