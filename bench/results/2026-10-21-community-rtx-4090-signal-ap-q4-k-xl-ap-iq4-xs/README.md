# Community benchmark on NVIDIA GeForce RTX 4090: agentionai Signal 3.8 Flash Next (AP-Q4_K_XL and AP-IQ4_XS)

Measured on 2026-10-21 by clothespin. Three configurations of agentionai's Signal fine-tune on one PC (RTX 4090, Ryzen 9 7950X3D,
93.5 GiB RAM), each run three or four times with one server start per run, plus a comparison of `--adapt-*` against the engine's default
and one of `--kv int8` against `--kv q4_0`. This is a results-only submission: it holds the data behind the speeds that
[#2041](https://github.com/Niko1221/Strata/pull/2041) quotes in `docs/SIGNAL_AP_Q4_K_XL.md` and `docs/MODELS.md`. #2041 is the code and
documentation change that adds `--family signal`; nothing in this folder depends on it being merged. Main limitation: one PC with a desktop
session open, and memory pressure and recovered storage read errors in the kernel log during some of the runs (see
[Conditions during the runs](#conditions-during-the-runs)). The speeds move from run to run; please read them as that PC's, not as
general numbers. This is the community guide's quick check (`tools/strata_bench.py`), not the draft standard protocol: the protocol has a
profile only for the original Qwen3.8-Flash-Next and says fine-tunes need their own.

## Hardware and software

- GPU and VRAM: NVIDIA GeForce RTX 4090, 24564 MiB; 178 MiB in use before every run; power limit 600 W (the default, not changed).
  CPU: AMD Ryzen 9 7950X3D (16 cores, 32 threads); installed RAM 93.5 GiB (95712 MiB). Storage: the model files are on a bcachefs volume on an
  NVMe SSD (make and model not recorded). PCIe link: not measured.
- Swap: `/dev/zram0` (zstd, 23.4 GB, priority 100) and an NVMe partition (77.5 GB, priority -1); `vm.swappiness` 180.
- OS: Linux 7.2.11-arch1-1; GPU driver 615.78.08; CUDA toolkit 13.4 (`nvcc` V13.4.92); Python 3.14.7. The CPU governor was `powersave` during
  every run (read into each `pre-run-state.txt`; not changed).
- Strata: the benchmark tools are `tools/strata_bench.py` and `tools/ab_engine.py` at commit `361b1393` (the head of the branch of #2041 whose
  tree the speed runs used); both files are identical on `main` (`9de04cd4`). Engine 0.1.46.3 built from source on this PC (arch 89, source hash
  `c87773ed5df25479`, vision encoder source `41b0903f5d532e38`, vision on the GPU). Every run's `pre-run-state.txt` records this.
- Background workloads: a desktop session was open during all runs (the Hyprland compositor, a web browser, the Steam client with no game, the coding agent that
  drove the runs); llama-swap was running with no model loaded; another GPU server on this PC was stopped. The five busiest processes at the start
  of each run are in its `pre-run-state.txt`.

## What is in this folder

- `runs/<label>/`: one benchmark run each: `results.json` (every request: tokens, timings, errors, the machine facts), `README.md` (the tool's own
  report), `engine-log-excerpt.txt`, `bench-console.txt`, `pre-run-state.txt` and `post-run-state.txt` (GPU, memory, load average, governor, busiest
  processes and the configuration at the start and the end). Labels: `pass1-` to `pass3-` for the three configurations A, B and C (C2 is a fourth
  run of C), and `kv-1-`/`kv-2-` for the `--kv` comparison.
- `ab/<label>/`: the `--adapt-*` comparison (`ab_engine.jsonl` has every request, `ab-console.txt` the console, `pre-run-state.txt` the start).
- `configs/`: the four run configurations and, for each, the engine's log file. Every start of a configuration appended to its file, so each holds
  several starts and is not split by run; each run's own start-up lines are in its `engine-log-excerpt.txt`.
- `sampler.csv`: the engine's resident memory, GPU memory, clock, power, temperature, utilization and the PC's available memory every 10 s,
  2026-10-21 (PDT) 00:54:43 to 01:47:16. It covers the second half of the `--adapt-*` comparison at 100 tokens and everything after it; the
  passes 1 and 2 of the three configurations were not sampled.
- `kernel-log-events.txt`: the kernel messages of the whole window that matter here (see below). `scripts/`: the runner scripts as they were run
  (the paths in them are replaced by placeholders), `make_tables.py` and `events_by_run.py`, which rebuild the tables below from the data.
- Home folders, the host name and the user name are replaced by placeholders: `<HOME>`, `<HOST>`, `<USER>`; model and data folders by
  `<MODEL_DATA>` and `<DATA>`; the Strata folder by `<STRATA_ROOT>`.

## Model and configuration

- Model: agentionai/Signal-3.8-Flash-Next-GGUF at revision `eba565be` (the revision `setup.py` pins in #2041). `AP-Q4_K_XL`: 101,142,769,984 bytes, SHA-256
  `427a7a10dd5a98d77c71be62a89d14e7408fc61a84c6efe889393852282cd3c6`. `AP-IQ4_XS`: 90,447,294,816 bytes, SHA-256
  `7fadb6b29035377204aed0d0085d3f58cc65fc7b4c3aa79f8f3f84fdfc304529`. Both files were hashed again on 2026-10-21 between 02:39 and 02:42 (PDT), after the runs, and match these values.
- Vision encoder: Signal's own `mmproj-F16.gguf`, loaded in A and B (`--vision`); no picture was sent in any test. C has no encoder.
- A: AP-Q4_K_XL through `setup.py --family signal --model AP-Q4_K_XL` of #2041 (2026-10-21, into an empty data folder); the config is the one setup
  wrote. B: AP-IQ4_XS the same way (2026-10-19, engine 0.1.45.3; the config is the one setup wrote then). C: AP-Q4_K_XL packed and configured by hand
  as `docs/SIGNAL_AP_Q4_K_XL.md` describes (2026-10-11).
- A and C differ in six settings at once, plus the encoder, so the results do not say which of them matters: A and B have `--max-context 131072`,
  every expert kept in RAM, `--ple-gguf ... --ple-io ram`, `--spec-min-p 0.5`, and `--vision --vram-reserve-mib 700`; C has `--max-context 262144`,
  `--resident-budget-gib 67`, `--pcie-frac 0.35`, `--pool-workers 8`, `--spec-min-p 0.70` and no encoder. All use `--kv int8` (except the
  `kv-*-q4_0` runs), `--kv-resident 32768`, `--spec 4`, `--mtp` (the original model's draft head), `--prefill auto`, `--expert-cache auto`
  and `data/expert-profile.bin` (the base model's expert ranking). Reasoning off for the suite, temperature 0. The experimental speed projection
  was not used.

```text
# A (configs/setup-ap-q4_k_xl.json)
<STRATA_ROOT>/engine/strata --pack <MODEL_DATA>/ap-q4kxl/packs/signal-ap-q4_k_xl --native <MODEL_DATA>/ap-q4kxl-gguf/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf --ple-gguf <MODEL_DATA>/ap-q4kxl-gguf/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf --embd-gguf <MODEL_DATA>/ap-q4kxl/packs/signal-ap-q4_k_xl/token-embd-bf16.gguf --expert-profile <STRATA_ROOT>/data/expert-profile.bin --expert-cache auto --prefill auto --spec 4 --spec-min-p 0.5 --mtp <MODEL_DATA>/ap-q4kxl/mtp/rt --max-context 131072 --kv int8 --ple-io ram --kv-resident 32768 --vision --vram-reserve-mib 700
# B (configs/setup-ap-iq4_xs.json)
<STRATA_ROOT>/engine/strata --pack <MODEL_DATA>/ap-iq4xs/packs/signal-ap-iq4_xs --native <MODEL_DATA>/ap-iq4xs/models/signal-AP-IQ4_XS/Signal-3.8-Flash-Next-AP-IQ4_XS.gguf --ple-gguf <MODEL_DATA>/ap-iq4xs/models/signal-AP-IQ4_XS/Signal-3.8-Flash-Next-AP-IQ4_XS.gguf --embd-gguf <MODEL_DATA>/ap-iq4xs/packs/signal-ap-iq4_xs/token-embd-bf16.gguf --expert-profile <STRATA_ROOT>/data/expert-profile.bin --expert-cache auto --prefill auto --spec 4 --spec-min-p 0.5 --mtp <MODEL_DATA>/ap-iq4xs/mtp/rt --max-context 131072 --kv int8 --ple-io ram --kv-resident 32768 --vision --vram-reserve-mib 700
# C (configs/docs-handbuilt.json)
<STRATA_ROOT>/engine/strata --pack <DATA>/packs/signal-ap-q4_k_xl --native <DATA>/models/agentionai-signal/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf --embd-gguf <DATA>/models/agentionai-signal/signal-ap-q4_k_xl-embd-bf16.gguf --expert-profile <STRATA_ROOT>/data/expert-profile.bin --expert-cache auto --prefill auto --spec 4 --mtp <DATA>/mtp/rt --max-context 262144 --kv int8 --kv-resident 32768 --resident-budget-gib 67 --pcie-frac 0.35 --spec-min-p 0.70 --pool-workers 8
```

## Method

- `scripts/run_one.sh LABEL CONFIG` runs `python tools/strata_bench.py --config CONFIG --out DIR` (suite 1, 3 runs per test, thinking off,
  temperature 0). The benchmark starts the server itself from the configuration, once per run; loading is not timed. Speeds are the engine's own
  timings; first-token times are measured by the client over HTTP. Short chat: the three questions of `tools/ab_engine.py`, up to 100 new
  tokens, 3 runs. 4K and 16K prompts: generated word lists, 24 new tokens, 3 fresh prompts each. Agent session: a system prompt and four tools, then
  5 further turns that each add about 1500 words of a project file and continue from the model's own earlier answers, in 3 sessions of 6 turns; the
  figures here use turns 2 to 6 of each session (the first turn has nothing to reuse). The tool's own `README.md` in each run folder has its full
  method text.
- Before every run `run_one.sh` wrote `pre-run-state.txt` (GPU, llama-swap's running models, memory, load average, governor, busiest processes) and after
  it `post-run-state.txt`. The `--adapt-*` comparison (`scripts/ab_run.sh`) refuses to start when the GPU has more than 2000 MiB in use or llama-swap has a
  model loaded.
- Order (start times are in the table of the conditions): pass 1: A, C, B; pass 2: B, C, A; then the two `--adapt-*` comparisons, then
  `--kv int8` and `--kv q4_0` alternating twice; then pass 3: B, C, C2 (a fourth run of C), A.
- `--adapt-*`: `tools/ab_engine.py`, config C, 4 rounds with the two arms alternating, `--max-new` 100 and 512; arm `default` against arm
  `adapt` (`--adapt-every 1 --adapt-swaps 80 --adapt-decay 0.97`, the values the setup calibration chose). The figures are medians over the three
  short chats and the long prompt of each round (16 requests per arm). `kv`: config C and the same with `--kv q4_0`, two runs of each, alternating.
- Statistics: the summary table gives the median over all requests of all runs of a configuration, with the slowest and fastest request as the range. The
  per-run tables give the median of the runs' own medians (the figure the documentation of #2041 quotes), each run's median and the range of all requests.
  `scripts/make_tables.py summary|perrun|start|ab` rebuilds all of them from `runs/` and `ab/`.

## Results

All figures are from `results.json`. Failed requests: none in any run; skipped tests: none.

### Summary (all requests of all runs of a configuration)

| Configuration | Test | Requests | Actual prompt tokens | Reused tokens | Generated tokens | Prompt tok/s median (range) | Decode tok/s median (range) | First token s median (range) |
| --- | --- | ---: | --- | --- | --- | --- | --- | --- |
| A  AP-Q4_K_XL, config setup writes | short chat | 27 | 46 (43-51) | 0 (0-0) | 100 (100-100) | not measured | 60.9 (44.8-75.5) | 0.53 (0.39-0.70) |
| A  AP-Q4_K_XL, config setup writes | 4K prompt, fresh | 9 | 4019 (4019-4019) | 0 (0-0) | 24 (24-24) | 1413 (1180-1488) | not measured | 2.87 (2.73-3.44) |
| A  AP-Q4_K_XL, config setup writes | 16K prompt, fresh | 9 | 16058 (16058-16058) | 0 (0-0) | 24 (24-24) | 2670 (2453-2734) | not measured | 6.04 (5.90-6.57) |
| A  AP-Q4_K_XL, config setup writes | agent session, turns 2-6 | 45 | 9059 (4090-14709) | 5687 (626-11889) | 64 (20-64) | not measured | 75.6 (56.0-99.9) | 2.96 (2.73-42.21) |
| B  AP-IQ4_XS, config setup writes | short chat | 27 | 46 (43-51) | 0 (0-0) | 100 (100-100) | not measured | 72.4 (57.4-94.4) | 0.43 (0.29-0.59) |
| B  AP-IQ4_XS, config setup writes | 4K prompt, fresh | 9 | 4019 (4019-4019) | 0 (0-0) | 24 (24-24) | 1722 (1436-1852) | not measured | 2.36 (2.19-2.82) |
| B  AP-IQ4_XS, config setup writes | 16K prompt, fresh | 9 | 16058 (16058-16058) | 0 (0-0) | 24 (24-24) | 3152 (2923-3325) | not measured | 5.12 (4.86-5.52) |
| B  AP-IQ4_XS, config setup writes | agent session, turns 2-6 | 45 | 9053 (4087-14708) | 5625 (625-11889) | 64 (40-64) | not measured | 90.6 (64.1-114.3) | 2.44 (2.20-4.22) |
| C  AP-Q4_K_XL, the document's hand-built config | short chat | 36 | 46 (43-51) | 0 (0-0) | 100 (100-100) | not measured | 55.3 (38.9-72.1) | 0.49 (0.37-0.65) |
| C  AP-Q4_K_XL, the document's hand-built config | 4K prompt, fresh | 12 | 4019 (4019-4019) | 0 (0-0) | 24 (24-24) | 1341 (331-1511) | not measured | 3.05 (2.68-12.17) |
| C  AP-Q4_K_XL, the document's hand-built config | 16K prompt, fresh | 12 | 16058 (16058-16058) | 0 (0-0) | 24 (24-24) | 2295 (875-2407) | not measured | 7.04 (6.70-18.38) |
| C  AP-Q4_K_XL, the document's hand-built config | agent session, turns 2-6 | 60 | 9056 (4090-14711) | 5686 (626-11892) | 64 (15-64) | not measured | 68.0 (48.2-96.2) | 2.99 (2.53-9.78) |
| C with --kv int8 (the same config as C, two more runs) | short chat | 18 | 46 (43-51) | 0 (0-0) | 100 (100-100) | not measured | 59.9 (52.3-70.0) | 0.42 (0.33-0.51) |
| C with --kv int8 (the same config as C, two more runs) | 4K prompt, fresh | 6 | 4019 (4019-4019) | 0 (0-0) | 24 (24-24) | 1478 (1200-1503) | not measured | 2.74 (2.70-3.37) |
| C with --kv int8 (the same config as C, two more runs) | 16K prompt, fresh | 6 | 16058 (16058-16058) | 0 (0-0) | 24 (24-24) | 2374 (2205-2399) | not measured | 6.79 (6.72-7.31) |
| C with --kv int8 (the same config as C, two more runs) | agent session, turns 2-6 | 30 | 9065 (4090-14710) | 5658 (626-11891) | 60 (3-64) | not measured | 71.1 (46.7-92.1) | 2.75 (2.54-4.01) |
| C with --kv q4_0 | short chat | 18 | 46 (43-51) | 0 (0-0) | 100 (100-100) | not measured | 61.1 (52.7-67.4) | 0.41 (0.32-0.49) |
| C with --kv q4_0 | 4K prompt, fresh | 6 | 4019 (4019-4019) | 0 (0-0) | 24 (24-24) | 1463 (1203-1496) | not measured | 2.77 (2.71-3.36) |
| C with --kv q4_0 | 16K prompt, fresh | 6 | 16058 (16058-16058) | 0 (0-0) | 24 (24-24) | 2319 (2143-2342) | not measured | 6.95 (6.88-7.53) |
| C with --kv q4_0 | agent session, turns 2-6 | 30 | 9064 (4083-14704) | 5694 (620-11885) | 58 (2-64) | not measured | 65.8 (46.4-87.3) | 2.77 (2.52-4.02) |

### Per run

**A  AP-Q4_K_XL, config setup writes** (3 runs, failed requests: 0)

| test | median of the runs | each run's median | slowest to fastest request |
| --- | --- | --- | --- |
| short chat, decode (tokens/s) | 62.7 | 62.7, 59.5, 64.4 | 44.8-75.5 (n=27) |
| short chat, first token (s) | 0.53 | 0.53, 0.57, 0.49 | 0.39-0.70 (n=27) |
| 4K prompt (tokens/s) | 1413 | 1473, 1413, 1324 | 1180-1488 (n=9) |
| 4K prompt, first token (s) | 2.87 | 2.75, 2.87, 3.06 | 2.73-3.44 (n=9) |
| 16K prompt (tokens/s) | 2670 | 2733, 2670, 2529 | 2453-2734 (n=9) |
| 16K prompt, first token (s) | 6.04 | 5.90, 6.04, 6.39 | 5.90-6.57 (n=9) |
| agent turns, decode (tokens/s) | 75.6 | 75.6, 72.3, 83.8 | 56.0-99.9 (n=45) |
| agent turns, first token (s) | 2.94 | 2.88, 2.94, 3.59 | 2.73-42.21 (n=45) |
| agent turns, prompt reused from the cache (%) | 69.4 | 69.4, 69.3, 69.4 | |

**B  AP-IQ4_XS, config setup writes** (3 runs, failed requests: 0)

| test | median of the runs | each run's median | slowest to fastest request |
| --- | --- | --- | --- |
| short chat, decode (tokens/s) | 78.4 | 78.4, 68.1, 80.2 | 57.4-94.4 (n=27) |
| short chat, first token (s) | 0.42 | 0.42, 0.49, 0.40 | 0.29-0.59 (n=27) |
| 4K prompt (tokens/s) | 1724 | 1849, 1713, 1724 | 1436-1852 (n=9) |
| 4K prompt, first token (s) | 2.35 | 2.19, 2.37, 2.35 | 2.19-2.82 (n=9) |
| 16K prompt (tokens/s) | 3155 | 3290, 3142, 3155 | 2923-3325 (n=9) |
| 16K prompt, first token (s) | 5.12 | 4.90, 5.14, 5.12 | 4.86-5.52 (n=9) |
| agent turns, decode (tokens/s) | 94.7 | 95.9, 85.1, 94.7 | 64.1-114.3 (n=45) |
| agent turns, first token (s) | 2.44 | 2.38, 2.44, 2.85 | 2.20-4.22 (n=45) |
| agent turns, prompt reused from the cache (%) | 69.3 | 69.2, 69.3, 69.3 | |

**C  AP-Q4_K_XL, the document's hand-built config** (4 runs, failed requests: 0)

| test | median of the runs | each run's median | slowest to fastest request |
| --- | --- | --- | --- |
| short chat, decode (tokens/s) | 57.2 | 55.5, 48.5, 61.0, 59.0 | 38.9-72.1 (n=36) |
| short chat, first token (s) | 0.50 | 0.52, 0.56, 0.46, 0.48 | 0.37-0.65 (n=36) |
| 4K prompt (tokens/s) | 1479 | 1466, 433, 1492, 1492 | 331-1511 (n=12) |
| 4K prompt, first token (s) | 2.74 | 2.77, 9.29, 2.71, 2.71 | 2.68-12.17 (n=12) |
| 16K prompt (tokens/s) | 2372 | 2358, 875, 2394, 2387 | 875-2407 (n=12) |
| 16K prompt, first token (s) | 6.80 | 6.84, 18.37, 6.73, 6.76 | 6.70-18.38 (n=12) |
| agent turns, decode (tokens/s) | 70.0 | 68.4, 61.0, 71.6, 73.5 | 48.2-96.2 (n=60) |
| agent turns, first token (s) | 2.78 | 2.81, 8.89, 2.71, 2.75 | 2.53-9.78 (n=60) |
| agent turns, prompt reused from the cache (%) | 69.4 | 69.4, 69.4, 69.3, 69.3 | |

**C with --kv int8 (the same config as C, two more runs)** (2 runs, failed requests: 0)

| test | median of the runs | each run's median | slowest to fastest request |
| --- | --- | --- | --- |
| short chat, decode (tokens/s) | 59.9 | 59.9, 59.9 | 52.3-70.0 (n=18) |
| short chat, first token (s) | 0.42 | 0.42, 0.43 | 0.33-0.51 (n=18) |
| 4K prompt (tokens/s) | 1478 | 1484, 1472 | 1200-1503 (n=6) |
| 4K prompt, first token (s) | 2.74 | 2.73, 2.75 | 2.70-3.37 (n=6) |
| 16K prompt (tokens/s) | 2377 | 2370, 2384 | 2205-2399 (n=6) |
| 16K prompt, first token (s) | 6.78 | 6.80, 6.76 | 6.72-7.31 (n=6) |
| agent turns, decode (tokens/s) | 70.7 | 71.3, 70.1 | 46.7-92.1 (n=30) |
| agent turns, first token (s) | 2.74 | 2.72, 2.76 | 2.54-4.01 (n=30) |
| agent turns, prompt reused from the cache (%) | 69.3 | 69.3, 69.3 | |

**C with --kv q4_0** (2 runs, failed requests: 0)

| test | median of the runs | each run's median | slowest to fastest request |
| --- | --- | --- | --- |
| short chat, decode (tokens/s) | 61.1 | 60.8, 61.5 | 52.7-67.4 (n=18) |
| short chat, first token (s) | 0.41 | 0.40, 0.42 | 0.32-0.49 (n=18) |
| 4K prompt (tokens/s) | 1463 | 1464, 1463 | 1203-1496 (n=6) |
| 4K prompt, first token (s) | 2.77 | 2.77, 2.77 | 2.71-3.36 (n=6) |
| 16K prompt (tokens/s) | 2329 | 2317, 2341 | 2143-2342 (n=6) |
| 16K prompt, first token (s) | 6.92 | 6.95, 6.88 | 6.88-7.53 (n=6) |
| agent turns, decode (tokens/s) | 67.1 | 65.7, 68.4 | 46.4-87.3 (n=30) |
| agent turns, first token (s) | 2.76 | 2.79, 2.74 | 2.52-4.02 (n=30) |
| agent turns, prompt reused from the cache (%) | 69.4 | 69.3, 69.4 | |

### `--adapt-*` against the engine's default (config C, 4 rounds)

Decode tokens/s, median over the requests of the arm:

| comparison | first arm | second arm | pairs |
| --- | --- | --- | --- |
| ab-adapt-max100 | default 56.7 (n=16) | adapt 48.5 (n=16) | default faster in 16 of 16 pairs |
| ab-adapt-max512 | default 60.8 (n=16) | adapt 56.0 (n=16) | default faster in 15 of 16 pairs |

The three `--adapt-*` settings made the first question's longer answers shorter in the 512-token comparison, so the texts were not the same there.

## Conditions during the runs

Start of each run (from `pre-run-state.txt`; the load average is the 1-minute figure at the moment of the snapshot, after the previous server had been stopped):

| run | started (PDT, 2026-10-21) | 1-minute load average at start | available memory at start (MiB) | GPU memory in use at start | seconds measured |
| --- | --- | ---: | ---: | --- | ---: |
| pass1-A-setup-ap-q4_k_xl | 00:10:37 | 1.31 | 69734 | 178 MiB | 118 |
| pass2-A-setup-ap-q4_k_xl | 00:38:59 | 31.14 | 79801 | 178 MiB | 123 |
| pass3-A-setup-ap-q4_k_xl | 01:41:19 | 5.15 | 80611 | 178 MiB | 164 |
| pass1-B-setup-ap-iq4_xs | 00:21:58 | 5.40 | 80360 | 178 MiB | 96 |
| pass2-B-setup-ap-iq4_xs | 00:29:28 | 0.93 | 79951 | 178 MiB | 103 |
| pass3-B-setup-ap-iq4_xs | 01:30:59 | 5.74 | 80667 | 178 MiB | 102 |
| pass1-C-docs-handbuilt-ap-q4_k_xl | 00:18:32 | 1.03 | 78480 | 178 MiB | 122 |
| pass2-C-docs-handbuilt-ap-q4_k_xl | 00:32:13 | 8.17 | 80278 | 178 MiB | 284 |
| pass3-C-docs-handbuilt-ap-q4_k_xl | 01:34:21 | 6.73 | 81059 | 178 MiB | 116 |
| pass3-C2-docs-handbuilt-ap-q4_k_xl | 01:37:49 | 5.23 | 81094 | 178 MiB | 117 |
| kv-1-int8 | 01:16:58 | 4.62 | 80653 | 178 MiB | 116 |
| kv-2-int8 | 01:23:55 | 6.04 | 80369 | 178 MiB | 115 |
| kv-1-q4_0 | 01:20:27 | 5.48 | 80798 | 178 MiB | 118 |
| kv-2-q4_0 | 01:27:20 | 5.69 | 80427 | 178 MiB | 114 |

Kernel messages in each run's window (`kernel-log-events.txt`; the count of each kind):

| run | start-end (PDT) | allocation failures | allocation stalls | zram swap write errors | bcachefs read errors (recovered) |
| --- | --- | ---: | ---: | ---: | ---: |
| runs/pass1-A-setup-ap-q4_k_xl | 00:10:37-00:15:15 | 0 | 0 | 0 | 0 |
| runs/pass1-C-docs-handbuilt-ap-q4_k_xl | 00:18:32-00:21:58 | 0 | 0 | 0 | 2 |
| runs/pass1-B-setup-ap-iq4_xs | 00:21:58-00:24:25 | 0 | 0 | 0 | 1 |
| runs/pass2-B-setup-ap-iq4_xs | 00:29:28-00:32:13 | 0 | 0 | 0 | 1 |
| runs/pass2-C-docs-handbuilt-ap-q4_k_xl | 00:32:13-00:38:59 | 2 | 0 | 10 | 0 |
| runs/pass2-A-setup-ap-q4_k_xl | 00:38:59-00:45:47 | 0 | 6 | 0 | 0 |
| ab/ab-adapt-max100 | 00:47:06-01:01:38 | 0 | 0 | 0 | 0 |
| ab/ab-adapt-max512 | 01:01:38-01:16:58 | 0 | 0 | 0 | 5 |
| runs/kv-1-int8 | 01:16:58-01:20:27 | 0 | 0 | 0 | 1 |
| runs/kv-1-q4_0 | 01:20:27-01:23:55 | 0 | 0 | 0 | 1 |
| runs/kv-2-int8 | 01:23:55-01:27:20 | 0 | 0 | 0 | 0 |
| runs/kv-2-q4_0 | 01:27:20-01:30:59 | 0 | 0 | 0 | 0 |
| runs/pass3-B-setup-ap-iq4_xs | 01:30:59-01:34:21 | 1 | 0 | 0 | 1 |
| runs/pass3-C-docs-handbuilt-ap-q4_k_xl | 01:34:21-01:37:49 | 0 | 0 | 0 | 2 |
| runs/pass3-C2-docs-handbuilt-ap-q4_k_xl | 01:37:49-01:41:06 | 0 | 0 | 0 | 0 |
| runs/pass3-A-setup-ap-q4_k_xl | 01:41:19-01:46:03 | 3 | 0 | 10 | 0 |

events in the file: 46; inside no run window: 0

- Page allocation failures and stalls are the kernel failing to allocate memory for a process (the stalls are 10 to 17 s); the swap write errors are
  on `/dev/zram0`, the compressed-RAM swap (`253:0`), not on a disk. They came with the engine holding about 66 GiB of the 93.5 GiB while a desktop
  session was open. `sampler.csv` has the PC's available memory: its lowest value in run 3 of A was 9,500 MiB, against 20,072 MiB in run 3 of C and
  20,810 MiB in run 3 of B.
- The bcachefs lines are checksum errors on reads of the two model files, each followed by "successful retry, self healing": the filesystem read the
  data again and it passed. They happen while a server loads its model. Reading the same two files front to back with `sha256sum` after the runs (no engine, no GPU, the memory pressure gone) produced 4 more of them in 129 s, with both hashes correct. A search of the kernel log since 2026-10-17 for PCIe AER, corrected and uncorrected error messages and NVMe I/O, timeout, controller and reset messages found none.
- Run 2 of C (`pass2-C`): the 4K and 16K prompts ran at 433 and 875 tokens/s with first tokens of 9.3 and 18.4 s, against 1466 to 1492 and 2358 to
  2394 tokens/s and about 2.7 and 6.8 s in the other three runs of C. The start load average was 8.2; it has 2 allocation failures and 10 zram swap
  write errors. The cause is not established. The run stays in every table.
- Run 3 of A (`pass3-A`): the last turn of the first agent session took 42.2 s to its first token (it read 2,819 new tokens at 66.9 tokens/s; the
  other 44 turns of A took 2.7 to 5.9 s). The sampler has no sample between 01:44:47 and 01:45:06 (the interval is normally 10 s), and the two samples
  around that gap read 0 % and 19 % utilization at 210 MHz and 19.6 W. The run has 3 allocation failures and 10 zram swap write errors. The cause is
  not established. The turn stays in every table.
- Run 2 of A (`pass2-A`): the 1-minute load average at its start was 31.1, and the log has 6 allocation stalls of 10 to 17 s in desktop programs
  between 00:41:02 and 00:42:59. Its 4K and 16K prompt rates lie between those of the other two runs (1413 against 1473 and 1324; 2670 against 2733 and
  2529), but its short-answer and agent decode medians are the lowest of the three (59.5 against 62.7 and 64.4; 72.3 against 75.6 and 83.8). It is
  not treated as an outlier, and the tables include it.
- Run 2 of B (`pass2-B`): short answers 68.1 tokens/s against 78.4 and 80.2, the 4K prompt 1713 against 1849 and 1724. No cause was found: its window
  has one recovered bcachefs read error, and run 1 of B, which was fast, had one too.

## Correctness and limitations

- No output was checked for correctness here: the suite measures speed. Output quality against the base model, the draft head's acceptance on this
  fine-tune, and anything with pictures were not measured. AP-IQ4_XS received no picture at all.
- One PC, one engine build, thinking off, temperature 0, short prompts (the longest is 16K tokens). The desktop session, the `powersave` governor
  and the memory pressure above are part of these numbers. Windows, AMD, other cards and other RAM sizes were not tested.
- The runs are not a randomized design: the order of the configurations changed between passes but the runs of one pass followed each other.
- The same files read by a plain `sha256sum` produced the same kind of bcachefs read errors (see above), so the PC's storage path is not known to be
  healthy; the benchmark did not depend on corrupted data (each error was recovered, and the hashes of both files match the published ones), but the
  timings of a load may include the retry.
