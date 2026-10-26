#!/usr/bin/env bash
# Assemble a portable Linux x86_64 CUDA bundle.
# Build without a GPU; qualify with the shared Anima smoke test.
# Usage: bash build-scripts/build_portable_cuda.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${THENOISE_ROOT:-${RUNNER_TEMP:-/tmp}/thenoise-cuda-build/thenoise}"
PBS_TAG="${PBS_TAG:-20260901}"
PBS_PY="${PBS_PY:-3.14.7}"
PYVER="${PYVER:-3.14}"
TORCH_VER="${TORCH_VER:-2.14}"
TORCHVISION_VER="${TORCHVISION_VER:-0.29}"
TORCH_INDEX="${TORCH_INDEX:-https://download.pytorch.org/whl/cu132}"

case "$ROOT" in
  /*) ;;
  *) echo "error: THENOISE_ROOT must be an absolute path" >&2; exit 2 ;;
esac
case "$(realpath -m "$ROOT")" in
  /|/bin|/etc|/home|/lib|/opt|/tmp|/usr|/var)
    echo "error: unsafe THENOISE_ROOT: $ROOT" >&2; exit 2 ;;
esac
if [ -e "$ROOT" ] || [ -L "$ROOT" ]; then
  echo "error: refusing to overwrite existing THENOISE_ROOT: $ROOT" >&2
  echo "Choose a new output path or explicitly remove a previous build." >&2
  exit 2
fi

mkdir -p "$(dirname "$ROOT")"
TMP="$(mktemp -d "${ROOT}.download.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PBS_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}/cpython-${PBS_PY}+${PBS_TAG}-x86_64-unknown-linux-gnu-install_only.tar.gz"

echo "[cuda] Fetching standalone CPython ${PBS_PY}"
curl -fLsS --retry 3 "$PBS_URL" -o "$TMP/python.tar.gz"
tar -xzf "$TMP/python.tar.gz" -C "$TMP"
[ -x "$TMP/python/bin/python${PYVER}" ] || {
  echo "error: Python ${PYVER} missing from standalone distribution" >&2; exit 1;
}
mv "$TMP/python" "$ROOT"

PY="$ROOT/bin/python${PYVER}"
SP="$ROOT/lib/python${PYVER}/site-packages"
export PIP_DISABLE_PIP_VERSION_CHECK=1
"$PY" -m pip install --no-cache-dir --upgrade pip setuptools wheel

echo "[cuda] Installing CUDA PyTorch from $TORCH_INDEX"
"$PY" -m pip install --no-cache-dir \
  --index-url "$TORCH_INDEX" --extra-index-url https://pypi.org/simple \
  "torch==${TORCH_VER}" "torchvision==${TORCHVISION_VER}"

"$PY" - "$ROOT/cuda-constraints.txt" <<'PY'
import importlib.metadata as metadata
import sys
import torch

assert torch.version.cuda is not None, f"Not CUDA PyTorch: {torch.__version__}"
assert torch.version.hip is None, f"Unexpected ROCm build: {torch.__version__}"
with open(sys.argv[1], 'w', encoding='utf-8') as f:
    for name in ('torch', 'torchvision'):
        f.write(f'{name}=={metadata.version(name)}\n')
print('CUDA PyTorch:', torch.__version__, 'CUDA runtime:', torch.version.cuda)
PY

echo "[cuda] Installing TheNoise and the model download helper"
"$PY" -m pip install --no-cache-dir -c "$ROOT/cuda-constraints.txt" \
  "$REPO_ROOT" 'huggingface-hub>=0.34.3'
mkdir -p "$ROOT/scripts"
cp "$REPO_ROOT/scripts/download.py" "$ROOT/scripts/download.py"

find "$ROOT" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$ROOT" -name '*.pyc' -delete
rm -rf "$SP/torch/test" "$SP/torch/benchmarks" \
  "$ROOT/lib/python${PYVER}/test" "$ROOT/lib/python${PYVER}/tkinter" \
  "$ROOT/lib/python${PYVER}/idlelib"

install -m 755 "$REPO_ROOT/build-scripts/thenoise-cuda-launcher" "$ROOT/bin/thenoise"

echo "[cuda] Verifying standalone bundle (GPU not required)"
(
  cd "$ROOT"
  "$PY" - <<'PY'
import importlib.metadata as metadata
import pathlib
import torch
import thenoise
import huggingface_hub
assert torch.version.cuda is not None and torch.version.hip is None
assert 'site-packages' in str(pathlib.Path(thenoise.__file__).resolve())
print('thenoise:', metadata.version('thenoise'))
print('torch:', torch.__version__, 'CUDA:', torch.version.cuda)
print('huggingface-hub:', huggingface_hub.__version__)
PY
  "$ROOT/bin/thenoise" --help >/dev/null
  "$PY" "$ROOT/scripts/download.py" --model anima --dry-run >/dev/null
)

"$PY" -m pip freeze > "$ROOT/requirements-frozen.txt"
{
  echo "TheNoise: $("$PY" -c "import importlib.metadata as m; print(m.version('thenoise'))")"
  echo "PyTorch: $("$PY" -c "import importlib.metadata as m; print(m.version('torch'))")"
  echo "CUDA runtime: $("$PY" -c 'import torch; print(torch.version.cuda)')"
  echo "Source commit: $(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "Built: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
} > "$ROOT/BUILD-INFO.txt"

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "THENOISE_ROOT=$ROOT" >> "$GITHUB_ENV"
fi

du -sh "$ROOT"
echo "[cuda] Done: $ROOT"
