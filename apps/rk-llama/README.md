# rk-llama

llama.cpp with the Rockchip NPU (RKNPU2) GGML backend, serving
Ministral-3-3B on the rk8s cluster.

Upstream: <https://github.com/invisiofficial/rk-llama.cpp> branch
`rknpu2` (commit `81eff6a` at time of build).

## Node prerequisites (rock-5b-01)

The vendor RKNN runtime (`librknnrt.so`) only works against the
Armbian **vendor** kernel's rknpu driver — not the mainline `rocket`
driver the rest of the boards run. rock-5b-01 was switched to
`linux-image-vendor-rk35xx` (6.1.115, rknpu v0.9.8). Note the boards
PXE-load their kernels from rb5009, so the vendor kernel had to be
staged to `sbc/armbian/rock-5b-01.igou.systems/{vmlinuz,initrd.img,board.dtb}`
on the router in addition to the apt install.

Model files on the node:

```
/var/lib/rk-llama/models/Ministral-3-3B-Instruct-2512-Q8_0.gguf  # served
/var/lib/rk-llama/models/gemma-4-E4B-it-Q8_0.gguf                # broken on fork, kept
/var/lib/rk-llama/models/LFM2-8B-A1B-Q8_0.gguf                   # broken on fork, kept
```

Q8_0 was chosen deliberately: the backend requantizes GGUF weights
into NPU-native formats, and Q8_0 → W8A8 is the recommended pairing
(precision levels match).

**Model selection findings** (driver v0.9.8, librknnrt 2.3.2 — the
fork bundles exactly the official v2.3.2 runtime):

- **Gemma-4-E4B** (the original goal): loads and generates at full
  speed (pp64 39 t/s, tg16 3.4 t/s) but produces degenerate
  prompt-echo output. The gemma3n/gemma4-E architecture family is
  broken in this fork (upstream issue #6); gemma-3-1b is broken
  even on the pure-CPU fallback pipeline. W8A8_STANDARD,
  W8A8_HADAMARD, and single-core NPU all tried.
- **LFM2-8B-A1B**: generates only special tokens despite being in
  the fork's benchmark table.
- **Granite-4.0-350M / Ministral-3-3B**: fully coherent output on
  the default W8A8 NPU pipeline — the NPU stack itself is healthy.

Retest the broken GGUFs (kept on the node) after upstream fixes.

## Image

Built from `Containerfile` in this directory. The binaries are
compiled natively on a board (`cmake -DLLAMA_RKNPU2=ON`) and copied
in; no registry is involved — the image is imported straight into
k3s containerd on the target node:

```
podman build --arch arm64 -t localhost/rk-llama-server:rknpu2-<sha> .
podman save -o rk-llama-image.tar localhost/rk-llama-server:rknpu2-<sha>
scp rk-llama-image.tar igou@rock-5b-01.igou.systems:/tmp/
ssh igou@rock-5b-01.igou.systems sudo k3s ctr images import /tmp/rk-llama-image.tar
```

## Caveats

- **One NPU client at a time.** Concurrent independent processes on
  the NPU can kernel-panic the board (upstream README), hence
  `replicas: 1` + `Recreate`.
- The NPU has a 4GB-per-IOMMU-domain limit; the backend spreads
  larger models across domains automatically (`RKNPU_DOMAINS` to
  partition manually).
- A daily `system_update` run on the boards can upgrade kernel
  packages on disk; the *booted* kernel comes from rb5009 TFTP, so
  module/kernel BTF mismatches reappear if the staged TFTP kernel is
  not refreshed alongside.

## Access

`http://rock-5b-01.igou.systems:30808/` (NodePort) — llama-server
web UI and OpenAI-compatible API at `/v1/chat/completions`.
