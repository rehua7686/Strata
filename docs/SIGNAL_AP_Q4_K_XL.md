# agentionai Signal AP-Q4_K_XL

Setup installs Signal (`--family signal`, sizes AP-Q4_K_XL and AP-IQ4_XS, images included): see
[What setup does](#what-setup-does). The rest of this page is the manual workflow setup automates, and what was checked.

Packed, loaded and run on Linux with an RTX 4090 (24 GB), Ryzen 9 7950X3D and 93 GB RAM on 2026-10-11, and run again
on the same machine on 2026-10-21 with Strata 0.1.46.3. The engine starts on this pack and answers requests; the
speeds quoted here were measured with `tools/strata_bench.py` on the 2026-10-21 runs, on the configuration shown with
each table, and no output-quality comparison against the base model was made. What was checked is listed at the end.

## The file

`agentionai/Signal-3.8-Flash-Next-GGUF`, **AP-Q4_K_XL**: one GGUF of 101,142,769,984 bytes (94.19 GiB), 1224
tensors, `general.architecture qwen4exp`, `general.finetune Signal`. Strata's geometry checks pass on it, and it
packs the way any quantization that compresses more than the experts does.

Against the file setup installs on this machine, Unsloth's UD-Q4_K_XL (four shards, 111,434,654,784 bytes):

| | Signal AP-Q4_K_XL | Unsloth UD-Q4_K_XL |
| --- | --- | --- |
| expert gate / up | Q4_K | Q4_K |
| expert down | IQ4_NL | Q5_1 |
| routed expert bytes | 67,947,724,800 (63.28 GiB) | 77,017,907,200 (71.72 GiB) |
| PLE lookup table | IQ4_NL | IQ4_NL |
| attention, shared experts, hyperconnection, PLE key/value, embedding, output head | Q6_K | Q8_0 |

Both expert types already have GPU kernels in the stock build: Q4_K (ggml type 12) is in the gate/up format list and
IQ4_NL (type 20) in the down list (`src/kernels/cuda/iq_kernels.cu:611`, `:615`), and `native_expert_supported()`
(`src/kernels/cuda/iq_kernels.cu:2790`) takes the pair at n_embd 2560, n_ff 640. No CMake option and no rebuild.
The file has to be fully downloaded first: `iq_pack.py` stops if a tensor's bytes are not all there.

## Pack the projections the kernels read as BF16

Build Strata normally; Python needs numpy, regex and gguf-py from the pinned dependency (`STRATA_GGUF_PY` can point
at its `gguf-py` directory).

```sh
.venv/bin/python tools/iq_pack.py \
  --gguf /path/to/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf \
  --out packs/signal-ap-q4_k_xl --compat-bf16
```

It converted 460 tensors: 96 F32 to BF16 exactly, and 364 with rounding - 266 Q6_K (worst error 0.00781), 96 Q8_0
(0.01440) and 2 IQ4_NL (0.00922). `dense.bin` is 1,538,035,200 bytes (1.43 GiB) against 1,485,688,320 for the
Unsloth pack. The rounding is relative to the GGUF's dequantized weights; it does not recover the original
checkpoint. Every tensor is listed in `conversions.json` and `compat-bf16.json`.

Use this model's own tokenizer, which the pack exports from the same file, and do not reuse another model's
`dense.bin`.

## The embedding comes from one extra file

Signal stores `token_embd.weight` as Q6_K. The native embedding path takes BF16 and the quantized types `is_iq()`
dequantizes - Q2_0, Q3_K, Q4_K, Q5_K, Q5_1, Q5_0, Q4_1, Q4_0, Q8_0 and the IQ types - and Q6_K is in that set only in
a build configured `-DSTRATA_Q6K_EXPERTS=ON` (`src/kernels/cuda/iq_kernels.cu:1917`, `:2702`, checked at
`src/core/native_head.cpp:124`). The stock engine therefore stops at startup saying
`native embedding: token_embd.weight is absent, of another shape, or of a type without a GPU dequantizer`. The pack
cannot carry the table - `iq_pack.py` leaves it in the GGUF - so `tools/embd_bf16_pack.py --gguf` dequantizes it to
BF16 and `--embd-gguf` hands the engine the file:

```sh
.venv/bin/python tools/embd_bf16_pack.py \
  --gguf /path/to/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf \
  --out /path/to/signal-ap-q4_k_xl-embd-bf16.gguf
```

On this machine that is 248,320 x 2,560 Q6_K turned into 1,271,398,400 bytes of BF16, worst rounding error 0.00036,
measured by the tool as it wrote (file 1,271,398,784 bytes). `--embd-gguf` replaces only the embedding table: the
output head still comes from the `--native` file (`src/program/generate.cpp:2897`, `src/core/native_head.cpp:116`),
and the head itself (`output.weight`, Q6_K) is read natively, because the decode path handles Q6_K with no option at
all (`src/kernels/cuda/native_mmvq.cu:2464`, `:2509`).

## The PLE table needs nothing extra

IQ4_NL is the format the table reader expects by default (`src/kernels/ngram.cpp:167`), and the loader takes
`per_layer_token_embd.weight` from the `--native` file when that file holds it
(`src/program/generate.cpp:2490`), so no `--ple-gguf`. The table is 26.8 GiB and stays on disk, read through mmap.

## Server

Save this as `strata-signal-ap-q4_k_xl.json`, replacing both `/path/to/` entries with the Signal file (the same one
twice - it is a single file, and it carries the PLE table):

```json
{
  "exe": "build/strata",
  "args": [
    "--pack", "packs/signal-ap-q4_k_xl",
    "--native", "/path/to/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf",
    "--embd-gguf", "/path/to/signal-ap-q4_k_xl-embd-bf16.gguf",
    "--expert-profile", "data/expert-profile.bin", "--expert-cache", "auto",
    "--prefill", "auto", "--spec", "4",
    "--mtp", "mtp/rt", "--max-context", "262144", "--kv", "int8", "--kv-resident", "32768",
    "--resident-budget-gib", "67", "--pcie-frac", "0.35", "--spec-min-p", "0.70", "--pool-workers", "8"
  ],
  "cwd": ".",
  "tokenizer": "packs/signal-ap-q4_k_xl/tokenizer",
  "model_name": "qwen3.8-flash-next-signal-ap-q4_k_xl",
  "log": "strata-signal-ap-q4_k_xl.log",
  "host": "127.0.0.1",
  "port": 12223
}
```

```sh
.venv/bin/python -m serve.server --engine strata --config strata-signal-ap-q4_k_xl.json --port 12223
```

The web interface is at `http://127.0.0.1:12223`, API clients use `http://127.0.0.1:12223/v1`. The port is the one
`--port` asks for (8095 if you leave it out); a launcher can pass its own, so the `port` entry in the file is only a
note to the reader. Images are not configured in this example (see [Images](#images)), and one graphics card runs one
engine: stop another server before starting this one.

The last four settings belong to one machine (RTX 4090, Ryzen 9 7950X3D, 93 GiB RAM) and are not general defaults.
`--pcie-frac` and `--spec-min-p` are what `setup.py`'s calibration chose for Signal there on 2026-10-11, each the
median of three rounds; `--pool-workers 8` is its pick from one run per value. On other hardware, calibrate again.
The calibration also chose `--adapt-every 1 --adapt-swaps 80 --adapt-decay 0.97`, from one run each. Measured with
`tools/ab_engine.py` on 2026-10-11 (four rounds, the arms alternating), the engine's default was faster: 44.3 against
35.9 tokens/s median for 100-token answers (faster in 16 of 16 pairs) and 51.4 against 46.1 tokens/s for answers of up
to 512 tokens (12 of 16). Measured again on 2026-10-21 with the configuration above (`--kv int8`, Strata 0.1.46.3,
four rounds, the arms alternating, median over the three short chats and the long prompt of each round): 56.7 against
48.5 tokens/s for 100-token answers (16 of 16 pairs) and 60.8 against 56.0 for up to 512 tokens (15 of 16). With the
three settings the first question's longer answers came out shorter (401-419 tokens against 512), so the texts were
not the same. Those three settings are left out.

`--kv int8` follows Signal's authors, who advise against a 4-bit value cache ("a 4-bit value cache makes long traces
degenerate"). The calibration and the 2026-10-11 comparison above ran with `--kv q4_0`. On 2026-10-21 the engine's log
for this configuration with `--kv q4_0` showed 195 MiB more VRAM for experts (6206 cache slots instead of 6132) and
1.4 GiB less of the KV cache in pinned RAM (1.69 against 3.09 GiB). `tools/strata_bench.py`, two runs of each, the two
alternating, measured (median of all requests) 59.9 tokens/s with `--kv int8` against 61.1 with `--kv q4_0` for short
answers, 71.1 against 65.8 in the agent session and 2374 against 2319 tokens/s for the 16K prompt. So 8-bit was not
slower in the agent session or on the long prompt, and the short-answer difference (1.2 tokens/s) is small beside the
spread within one run (52.3-70.0 tokens/s with `--kv int8`).

`--resident-budget-gib` caps only the RAM copy of the experts the GPU cache does not hold. With the 6141 cache slots
this card gets (15.81 GiB of VRAM) that is 18,435 experts, 47.47 GiB, and any budget from there up copies all of them
(with `--kv q4_0` and 6216 slots, the engine logged the same 47.28 GiB page-locked copy at 67 and at 69). The 26.8 GiB
PLE table is what gets streamed. Below 47.47 GiB, the least-used experts are read from the SSD instead.
That was the engine of 2026-10-11; the engine of 2026-10-21 (0.1.46.3) logs 6132 slots and a 51.11 GiB page-locked
copy for the configuration above (50.80 GiB with `--kv q4_0` and 6206 slots), and the comparison of budgets 67 and 69
was not repeated.

With exactly the configuration above (the paths of this machine; no images), on 2026-10-21 with Strata 0.1.46.3, the
server was ready 69-90 s after start (eight starts, `tools/ab_engine.py`). `tools/strata_bench.py` (3 runs per test,
thinking off, temperature 0), run four times on this configuration with one start each, measured:

| test | median of the runs | each run's median | slowest to fastest request |
|---|---|---|---|
| short chat, decode (up to 100 tokens) | 57.2 tokens/s | 55.5, 48.5, 61.0, 59.0 | 38.9-72.1 (36 answers) |
| short chat, first token | 0.50 s | 0.52, 0.56, 0.46, 0.48 | 0.37-0.65 |
| 4K prompt | 1479 tokens/s | 1466, 433, 1492, 1492 | 331-1511 (12 prompts) |
| 4K prompt, first token | 2.74 s | 2.77, 9.29, 2.71, 2.71 | 2.68-12.17 |
| 16K prompt | 2372 tokens/s | 2358, 875, 2394, 2387 | 875-2407 (12 prompts) |
| 16K prompt, first token | 6.80 s | 6.84, 18.37, 6.73, 6.76 | 6.70-18.38 |
| agent session, decode (turns 2-6) | 70.0 tokens/s | 68.4, 61.0, 71.6, 73.5 | 48.2-96.2 (60 turns) |
| agent session, first token (turns 2-6) | 2.78 s | 2.81, 8.89, 2.71, 2.75 | 2.53-9.78 |
| agent session, prompt reused from the cache | 69.4% | 69.4, 69.4, 69.3, 69.3 | 69.3-69.4% |

Run 2 is the slow one: its 4K and 16K prompts ran at 433 and 875 tokens/s with first tokens of 9.3 and 18.4 s, against
1466-1492 and 2358-2394 tokens/s and about 2.7 and 6.8 s in the other three. The kernel log has two page-allocation
failures during it (one in the engine while it loaded, one in the desktop compositor), the 1-minute load average at
its start was 8.2, and the machine's available memory was not sampled then. The cause is not established. The run
stays in the table; without it the medians of the runs would be 59.0 tokens/s for short answers and 1492 tokens/s for
the 4K prompt, against 57.2 and 1479.

The 4090 held 178 MiB before each run. A desktop session was open during all of them: a browser, the Steam client (no
game) and the coding agent that drove the runs.

`--mtp mtp/rt` is the original model's draft head, prepared by `tools/mtp_fetch.py`, `tools/mtp_pack.py` and
`tools/mtp_rt.py` as in the [OrcaRouter setup](ORCA.md); without `--mtp` the server drafts by lookup only. Signal
verifies every draft, and a fine-tune's acceptance is not the base model's. It has not been measured for Signal.

## What setup does

`setup.py --family signal --model AP-Q4_K_XL` (or `AP-IQ4_XS`) does the steps above by itself: it downloads the file
from a pinned revision and checks its SHA-256, packs it with `--compat-bf16`, writes the BF16 embedding beside the
pack (`token-embd-bf16.gguf`) and adds `--embd-gguf` to the config. With images on, it downloads Signal's own encoder
(`mmproj-F16.gguf`, 904 MB), saved as `mmproj-Signal-3.8-Flash-Next-F16.gguf`. Neither size asks on an AMD card: the
HIP engine has kernels for every format the two use - Q4_K experts run on an R9700 as UD-Q4_K_XL's, IQ3_S gate/up and
IQ4_NL downs as UD-IQ4_XS's ([QUANTS.md](QUANTS.md)) - though neither Signal file itself has run on AMD.

Run on the machine above on 2026-10-11 with the file already downloaded:
`./setup.sh --family signal --model AP-Q4_K_XL --gguf-dir <its folder> --vision gpu --build --yes --no-start`. It took
5 minutes, including the SHA-256 check of the 101 GB file and compiling the image encoder. The pack, the tokenizer and
the embedding file it wrote are byte for byte the ones built by hand above.

Run again on 2026-10-21 with Strata 0.1.46.3 (`setup.py --family signal --model AP-Q4_K_XL --data-dir <folder>
--gguf-dir <its folder> --vision gpu --no-start --yes`, into an empty data folder, the engine already built): 325 s,
including the SHA-256 check, the pack and the 5 GB MTP download. Its config is not the hand-built one above: 131072
tokens of context (setup's default on this card; the hand-built one has 262144), every expert kept in RAM instead of a
67 GiB budget (setup does that from about 80 GiB of RAM), the PLE table read from the GGUF into RAM (`--ple-gguf`,
`--ple-io ram`), images on (`--vision`, `--vram-reserve-mib 700`), `--spec-min-p 0.5` instead of 0.70, and neither
`--pcie-frac` nor `--pool-workers`; the KV cache is 8-bit in both. `tools/strata_bench.py` (3 runs per test, thinking
off, temperature 0), run three times with one start each, measured:

| test | median of the runs | each run's median | slowest to fastest request |
|---|---|---|---|
| short chat, decode (up to 100 tokens) | 62.7 tokens/s | 62.7, 59.5, 64.4 | 44.8-75.5 (27 answers) |
| short chat, first token | 0.53 s | 0.53, 0.57, 0.49 | 0.39-0.70 |
| 4K prompt | 1413 tokens/s | 1473, 1413, 1324 | 1180-1488 (9 prompts) |
| 4K prompt, first token | 2.87 s | 2.75, 2.87, 3.06 | 2.73-3.44 |
| 16K prompt | 2670 tokens/s | 2733, 2670, 2529 | 2453-2734 (9 prompts) |
| 16K prompt, first token | 6.04 s | 5.90, 6.04, 6.39 | 5.90-6.57 |
| agent session, decode (turns 2-6) | 75.6 tokens/s | 75.6, 72.3, 83.8 | 56.0-99.9 (45 turns) |
| agent session, first token (turns 2-6) | 2.94 s | 2.88, 2.94, 3.59 | 2.73-42.21 |
| agent session, prompt reused from the cache | 69.4% | 69.4, 69.3, 69.4 | 69.3-69.4% |

In run 3 the last turn of the first agent session took 42.2 s to its first token (the other 44 turns: 2.7-5.9 s, the
slowest of them, 5.9 s, also in that run). The sampler, which read the GPU every 10 s, shows it nearly idle for at
least 19 s during the agent part of that run, the kernel log has page-allocation failures in two desktop programs 30
seconds apart, and the machine's available memory was down to 9.3 GiB while the engine ran (18.8-20.9 GiB in the
other runs of that session). The cause is not established. The turn stays in the table.

Against the hand-built configuration's table above, setup's is faster for short answers (62.7 against 57.2 tokens/s),
the 16K prompt (2670 against 2372) and the agent session (75.6 against 70.0), and about the same for the 4K prompt
(1413 against 1479). The two differ in six settings at once (context, RAM budget, PLE table, speculation threshold,
the PCIe fraction and the pool workers), plus images, so this does not say which of them makes the difference.

AP-IQ4_XS (90,447,294,816 bytes) was run through setup on 2026-10-19 and again on 2026-10-21. Its header, read from
the first 32 MB of the file, differs from AP-Q4_K_XL's only in the routed experts' gate and up projections: IQ3_S
instead of Q4_K, 57,252,249,600 bytes of experts. IQ3_S gate/up with IQ4_NL downs is the pair Unsloth's UD-IQ4_XS
uses, which setup already runs on NVIDIA and AMD cards.

`setup.py --family signal --model AP-IQ4_XS --vision gpu` took 1766 s on 2026-10-19 with the engine of that day
(0.1.45.3), including the 90 GB download, its SHA-256 check, the pack, the BF16 embedding and the MTP head. Its config
has the same settings as AP-Q4_K_XL's setup config above (131072 tokens of context, every expert in RAM, images on).
`tools/strata_bench.py` (3 runs per test, thinking off, temperature 0), run three times on 2026-10-21 with one start
each, measured:

| test | median of the runs | each run's median | slowest to fastest request |
|---|---|---|---|
| short chat, decode (up to 100 tokens) | 78.4 tokens/s | 78.4, 68.1, 80.2 | 57.4-94.4 (27 answers) |
| short chat, first token | 0.42 s | 0.42, 0.49, 0.40 | 0.29-0.59 |
| 4K prompt | 1724 tokens/s | 1849, 1713, 1724 | 1436-1852 (9 prompts) |
| 4K prompt, first token | 2.35 s | 2.19, 2.37, 2.35 | 2.19-2.82 |
| 16K prompt | 3155 tokens/s | 3290, 3142, 3155 | 2923-3325 (9 prompts) |
| 16K prompt, first token | 5.12 s | 4.90, 5.14, 5.12 | 4.86-5.52 |
| agent session, decode (turns 2-6) | 94.7 tokens/s | 95.9, 85.1, 94.7 | 64.1-114.3 (45 turns) |
| agent session, first token (turns 2-6) | 2.44 s | 2.38, 2.44, 2.85 | 2.20-4.22 |
| agent session, prompt reused from the cache | 69.3% | 69.2, 69.3, 69.3 | 69.2-69.3% |

On the same setup config AP-IQ4_XS was faster than AP-Q4_K_XL: short answers 78.4 against 62.7 tokens/s, the 4K prompt
1724 against 1413, the 16K prompt 3155 against 2670 and the agent session 94.7 against 75.6. The runs differ by more
here than for AP-Q4_K_XL (short answers 68.1, 78.4 and 80.2 tokens/s); no cause was found for the lowest. Output
quality was not compared with AP-Q4_K_XL's, and no picture was sent to it.

## Images

Signal ships its own image encoder, `mmproj-F16.gguf`: a `qwen3vl_merger` projector to 2560 wide, the model's width,
in F16. With the configuration setup wrote, `strata-vision` loaded it in 0.7 s, and Signal answered (thinking off,
temperature 0):

- a drawn test picture (the number 7341 at the top, a red circle on the left, a blue square on the right, the word
  LIGHTHOUSE at the bottom), asked for each of them: "7341 red circle blue square lighthouse", 2.8 s; asked how many
  colored shapes: "2", 1.6 s;
- `docs/media/pagoda-preview.webp`, asked for two sentences: "This image shows a pixelated, isometric 3D scene
  featuring a multi-tiered pagoda on a floating island with cherry blossom trees and a small pond. A control panel on
  the left allows users to adjust settings like time, weather, and camera angle for this voxel-style environment.",
  2.7 s.

By hand: build the image encoder (setup does it with `--vision gpu`), add `"--vision", "--vram-reserve-mib", "700"`
to `args`, and give the config a block:

```json
"vision": {
  "exe": "engine/strata-vision",
  "mmproj": "/path/to/mmproj-F16.gguf",
  "model": "/path/to/Signal-3.8-Flash-Next-AP-Q4_K_XL.gguf",
  "gpu": true,
  "max_tokens": 1024
}
```

## Scope and validation

Checked on 2026-10-11 on the machine above:

- Header read: 1224 tensors with the keys and geometry the engine expects. `tools/strata_inspect.py` reports the
  routed experts use only quantizations Strata runs (Q4_K gate/up, IQ4_NL down), and names the weights this file
  stores differently from the files setup installs.
- `tools/iq_pack.py --compat-bf16` completed: `index.txt` (1081 rows), `native_experts.txt` (v3, 512 experts per
  layer, 67,947,724,800 bytes), `dense.bin`, `conversions.json`, `compat-bf16.json` and `tokenizer/`.
- `tools/embd_bf16_pack.py --gguf` completed: 1,271,398,784 bytes, worst rounding error 0.00036.
- Packing tests: `.venv/bin/python -m unittest discover -s tools -p test_iq_pack.py` - 35 tests, all pass. Two of them
  are for `tools/embd_bf16_pack.py --gguf`: a small Q6_K table in a model split over two files comes out as the
  BF16 rounding of gguf-py's dequantization, byte for byte, in more than one pass of rows; a missing tensor and a
  1-D tensor are refused.
- The engine started on the configuration above. Its log shows each piece landing where this document says it should:
  `--embd-gguf` read as "token embedding BF16 in mapped host memory (1212 MiB, 1.2 s)"; "302 canonical tensors skipped:
  served natively"; 300 native projection matrices, 2294.53 MiB, in 1.1 s; the PLE table read from the same GGUF as
  `--native` at 21487 rows/s; experts mmap'd in place with no `experts.bin`; 47.47 GiB of experts page-locked in RAM
  beside 15.81 GiB in the GPU cache, 63.28 GiB together, the size the header predicts; and the output head read
  natively at 521,472,000 bytes - 2,483,200 blocks of the engine's interleaved Q6_K layout, which is
  `output.weight`'s own block count. The log's wording there, "experimental native Q5_K head", is a fixed string at
  `src/program/generate.cpp:4497`, not a report of the tensor's type.
- The server answered the checks of the [OrcaRouter setup](ORCA.md) on that configuration: arithmetic (391), a Python
  function, a translation, a longer explanation, two requests sharing a 686-token prefix (the second, asked for the
  list's second-largest number, answered 98; it is 99, and with `--kv q4_0` it answered 100), and a cancelled stream
  followed by a correct answer (19), with one engine process throughout.

Not checked:

- Output quality against the base model is not measured, and neither is the draft head's acceptance rate on this
  fine-tune - Signal verifies every draft, but how often it accepts one is unknown here. The speeds above are one
  machine's; on other hardware, calibrate and watch the log for the engine's own complaints.
- AP-Q4_K_XL was checked as listed above. AP-IQ4_XS was run through setup and `tools/strata_bench.py` (above) and
  answered an arithmetic question (391), but none of the other checks listed here (the OrcaRouter list, pictures) was
  run on it. Q8_0 was not examined.
- Setup's download of the 101 GB AP-Q4_K_XL file (both runs above used `--gguf-dir`; AP-IQ4_XS's 90 GB download went
  through setup), setup on Windows, AMD cards, several GPUs,
  and the image encoder on the CPU.
- `tools/embd_bf16_pack.py --model` was not run end to end, because no safetensors checkpoint was on the machine. Its
  header was compared byte for byte with the one the previous code built, and the table is copied by the same loop,
  moved into a function. (`--gguf` was already there for Gyro-S's Q6_K table. This setup changed how it reads the
  file - through `iq_pack.py`'s model reader, so a split model works - and added `--tensor` and the printed rounding
  error. The tests above use a small table; the full-size run is the AP-Q4_K_XL one above.)
