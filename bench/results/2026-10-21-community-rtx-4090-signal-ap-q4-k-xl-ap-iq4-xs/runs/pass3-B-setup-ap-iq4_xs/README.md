# Community benchmark on NVIDIA GeForce RTX 4090

Measured on 2026-10-21 with `tools/strata_bench.py` (suite 1, 3 runs per test, medians with ranges). Speeds are the engine's own timings; first-token times are measured by the client over HTTP. Speed only: no correctness check was run.

## Hardware and software

- GPU and VRAM: NVIDIA GeForce RTX 4090, 24 GiB VRAM
- CPU: AMD Ryzen 9 7950X3D 16-Core Processor (16 cores, 32 threads); installed RAM: 93.5 GiB; storage: not measured
- OS: Linux 7.2.11-arch1-1; GPU driver: 615.78.08; CUDA: not read
- Strata: project 0.1.46.3, commit 361b1393; engine 0.1.46.3
- Background workloads and power limits: not recorded

## Model and configuration

- Model and quantization: signal-3.8-flash-next-ap-iq4_xs
- Context: 131072 tokens; parallel slots: 1
- Settings: the install's own configuration, unchanged; thinking off for the suite; temperature 0

```text
strata --pack signal-ap-iq4_xs --native Signal-3.8-Flash-Next-AP-IQ4_XS.gguf --ple-gguf Signal-3.8-Flash-Next-AP-IQ4_XS.gguf --embd-gguf token-embd-bf16.gguf --expert-profile expert-profile.bin --expert-cache auto --prefill auto --spec 4 --spec-min-p 0.5 --mtp rt --max-context 131072 --kv int8 --ple-io ram --kv-resident 32768 --vision --vram-reserve-mib 700
```

## Method

Run by `python tools/strata_bench.py` against the HTTP API of a Strata server (started by the benchmark from the install configuration); model loading is not timed. One warm-up chat and a 1K prompt are discarded first. Every prompt starts with a unique tag, so the conversation cache cannot help the fresh-prompt tests.

- short chat: the three questions of `tools/ab_engine.py`, up to 100 new tokens, 3 runs
- 4K / 16K prompts: generated word lists sized by a calibration request, 24 new tokens, 3 fresh prompts each
- agent session: system prompt and four tools, then 5 turns that each add about 1500 words of a project file and continue from the model's own earlier answers (the way agent clients resend a conversation), 64 new tokens per turn, 3 sessions; the cache numbers come from the answer's usage (`cached_tokens`) and timings (`prompt_n`)
- concurrency (when run): N requests sent at the same moment, total tokens over the wall time of the burst, latency over all requests

## Results

| Configuration | Actual prompt tokens | Reused tokens | Generated tokens | Runs | Prompt tok/s median and range | Decode tok/s median and range | TTFT seconds median and range |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| short chat | 46 (43-51) | 0 | 100 (100-100) | 9 | not measured | 80.2 (71.6-94.4) | 0.40 (0.31-0.59) |
| 4K prompt, fresh | 4019 (4019-4019) | 0 (0-0) | 24 cap | 3 | 1724.4 (1436.5-1802.2) | not measured | 2.35 (2.25-2.82) |
| 16K prompt, fresh | 16058 (16058-16058) | 0 (0-0) | 24 cap | 3 | 3154.7 (3076.5-3295.3) | not measured | 5.12 (4.90-5.25) |
| agent session, follow-up turns | 14695 (14694-14700) at the last turn | see below | up to 64 | 3 | see below | 94.7 (64.8-114.3) | 2.85 (2.30-4.22) |

Ranges are the lowest and highest of the runs; `Runs` counts requests that returned a token.

### Agent session (conversation cache)

Cache hit over the follow-up turns: 69.3 % (69.0-69.3); earlier-turn tokens read again per session: 74 (73-214) (earlier turns that the cache did not hold; the 13828 (13826-13828) new tokens of the files are read once); first turn (nothing cached) first token: 1.29 s (1.14-1.34).

| Turn (run 1) | Prompt tokens | Reused | Read | Prompt tok/s | First token (s) | Decode tok/s |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 609 | 0 | 609 | 464.7 | 1.345 | 59.7 |
| 1 | 4087 | 625 | 3462 | 828.7 | 4.223 | 69.3 |
| 2 | 5620 | 4080 | 1540 | 547.2 | 2.845 | 79.3 |
| 3 | 9053 | 5613 | 3440 | 965.2 | 3.593 | 80.5 |
| 4 | 11825 | 9046 | 2779 | 879.3 | 3.19 | 99.2 |
| 5 | 14700 | 11881 | 2819 | 906.8 | 3.147 | 64.8 |

Per-request data: `results.json`. Engine log lines from the start: `engine-log-excerpt.txt` (when this run started the server).

## Correctness and limitations

Not measured: this is a speed suite. The conversation uses the model's own replies, so token counts differ a little between runs. Machine details come from the server, `nvidia-smi`/`rocm-smi` and the OS; background load and power limits are not recorded. Total time of the suite: 102 s.
