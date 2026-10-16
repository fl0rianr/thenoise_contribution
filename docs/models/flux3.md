# Flux.3

**Newest Flux. Built to edit.**

Flux.3 is Black Forest Labs' third-generation Flux, released as a distilled
editing model: hand it one or more reference images plus an instruction and it
returns the edited image, leaving the parts you didn't mention alone. Plain
text-to-image works too. The released checkpoint is the small variant (5.5B
parameters).

- Text-to-image **and editing** (one or more reference images + instruction)
- Built-in defaults: **15 steps, guidance 1.0, euler** (CFG off)
- Any size you ask for, rounded up to a multiple of 16 px
- int8-convrot checkpoint (5.8 GB); the bf16 original is ~11 GB

> Commands below assume a dev checkout (`./thenoise.sh`, `.venv/bin/python`).
> On a [portable bundle](../setup.md) use `./bin/thenoise` and
> `./bin/python3` instead.

## Specs

| Spec | Data |
|---|---|
| Architecture | Distilled flow-map DiT, dim 3072 (Flux.2 packed 128-ch latent) |
| Checkpoint size | 5.8 GB int8-convrot · ~11 GB bf16 |
| VAE | Flux.2 VAE (shared with Flux.2 Klein) |
| Text encoder | Qwen3-VL 4B (the same file Mage-Flow uses) |
| Editing | ✓ |
| KV cache | — |
| Default settings | 1024×1024, 15 steps, guidance 1.0, euler |


## Performance (Strix Halo)

INT8-ConvRot, Distilled, 768x1024:

- Generate @ 15 steps : **~13.2 s**
- Edit @ 15 steps: ~34.4 s

## Examples

*Generated — 15 steps:*

<!-- image -->

*Edited — instruction: "…":*

| Before | After |
|---|---|
| <!-- before --> | <!-- after --> |

## Download

`scripts/download.py` has no Flux.3 entry. The checkpoint sits behind a login on
Hugging Face and there is no mirror to fall back on, so there is nothing the
script could fetch unattended. Grab three files yourself from https://huggingface.co/black-forest-labs/flux-3-image-klein-comfy:

| File | What
|---|---|---|
| `flux3_image_klein_sd_int8_convrot.safetensors` | the DiT |
| `flux2-vae.safetensors` | VAE |
| `qwen3vl_4b_int8_convrot.safetensors` | text encoder |

They can live anywhere — every path goes on the command line. The examples
below assume `./models/klein3/`. There is no Lemonade recipe for the
same reason there is no download entry: a recipe has to point at files the
installer can fetch by itself.

## Usage

Generate:

```bash
./thenoise.sh generate \
  --dit ./models/klein3/flux3_image_klein_sd_int8_convrot.safetensors \
  --vae ./models/klein3/flux2-vae.safetensors \
  --text-encoder ./models/klein3/qwen3vl_4b_int8_convrot.safetensors \
  --prompt "a red panda drinking tea in a bamboo forest" \
  --out panda.png
```

Edit — `--image` is repeatable and each image becomes a reference the model can
look at. The **first** image sets the output size (1024 on its longest side,
aspect preserved) unless you pass `--width`/`--height`:

```bash
./thenoise.sh edit \
  --dit ./models/klein3/flux3_image_klein_sd_int8_convrot.safetensors \
  --vae ./models/klein3/flux2-vae.safetensors \
  --text-encoder ./models/klein3/qwen3vl_4b_int8_convrot.safetensors \
  --image panda.png \
  --prompt "put the panda on a bar stool, keep its pose and fur exactly as they are" \
  --out panda_edited.png
```

Serve over HTTP with the web UI (open <http://localhost:8000/>) — the Edit tab
appears because this model supports editing:

```bash
./thenoise.sh serve \
  --dit ./models/klein3/flux3_image_klein_sd_int8_convrot.safetensors \
  --vae ./models/klein3/flux2-vae.safetensors \
  --text-encoder ./models/klein3/qwen3vl_4b_int8_convrot.safetensors \
  --host 127.0.0.1 --port 8000
```