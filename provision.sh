#!/usr/bin/env bash
# =============================================================================
#  H3 Long Video (Multi-Ref) — provisioner for RunPod
#  - ติดตั้ง ComfyUI_MiniMax_H3_Extender (+ requirements)
#  - วาง workflow H3_LongVideo_MultiRef.json ลงเมนู Workflows
#  - ดาวน์โหลดโมเดล + LoRA อัตโนมัติ (ข้ามไฟล์ที่มีแล้ว / resume ได้)
#
#  ใช้กับ image: hearmeman/comfyui-minimax-template  (ComfyUI 0.36 + H3 nodes)
#  Start command:  bash -c "curl -fsSL $REPO_RAW/provision.sh | bash; exec /start_script.sh"
#
#  ENV (ตั้งใน RunPod template):
#    REPO_RAW      = raw URL ของ repo นี้ (ใช้โหลด workflow)          [จำเป็น]
#    HF_TOKEN      = token HuggingFace (ไม่จำเป็น — repo เป็น public)
#    H3_QUANT      = int8 (default) | fp8 | bf16
#    H3_FL2VA      = 1 เพื่อโหลดโมเดล FL2VA (first/last frame) เพิ่ม ~23 GB
#    EXTRA_LORAS   = รายการ URL LoRA เพิ่มเติม คั่นด้วยช่องว่าง
#
#  Civitai (ต้องเป็นของ H3 เท่านั้น — LoRA ของ Wan/SDXL/Flux ใช้ไม่ได้):
#    CIVITAI_TOKEN  = API key ของ Civitai (แนะนำใส่เป็น RunPod Secret)
#    CIVITAI_BASE   = https://civitai.red (default) | https://civitai.com
#    CIVITAI_LORAS  = "versionId:ชื่อไฟล์.safetensors ..."  → models/loras
#    CIVITAI_MODELS = "versionId:ชื่อไฟล์.safetensors ..."  → models/diffusion_models
# =============================================================================
set -u

LOG=/workspace/h3_provision.log
[ -d /workspace ] || LOG=/h3_provision.log
exec > >(tee -a "$LOG") 2>&1
echo "==== H3 provision $(date) ===="

# ---- ที่อยู่ ComfyUI (ตรงกับ layout ของ Hearmeman runtime) --------------------
if [ -d /workspace ]; then ROOT=/workspace/ComfyUI; else ROOT=/ComfyUI; fi
NODES="$ROOT/custom_nodes"
MODELS="$ROOT/models"
WF_DIR="$ROOT/user/default/workflows"
mkdir -p "$NODES" "$WF_DIR" \
         "$MODELS/diffusion_models" "$MODELS/text_encoders" \
         "$MODELS/vae" "$MODELS/loras"

PIP="pip"; [ -x /opt/venv/bin/pip ] && PIP=/opt/venv/bin/pip

# ---- 1) Custom nodes (ต้องเสร็จก่อน ComfyUI เปิด) -----------------------------
install_node() {
  local url="$1" dir="$NODES/$(basename "$1" .git)"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only -q || echo "⚠️ pull failed: $dir (ใช้เวอร์ชันเดิม)"
  else
    git clone --depth 1 -q "$url" "$dir" || { echo "❌ clone failed: $url"; return; }
  fi
  [ -f "$dir/requirements.txt" ] && $PIP install -q -r "$dir/requirements.txt"
  echo "✅ node: $(basename "$dir")"
}
install_node https://github.com/tritant/ComfyUI_MiniMax_H3_Extender.git

# ---- 2) Workflow ---------------------------------------------------------------
if [ -n "${REPO_RAW:-}" ]; then
  curl -fsSL "$REPO_RAW/workflows/H3_LongVideo_MultiRef.json" \
       -o "$WF_DIR/H3_LongVideo_MultiRef.json" \
    && echo "✅ workflow: H3_LongVideo_MultiRef.json" \
    || echo "⚠️ โหลด workflow ไม่ได้ — เช็ค REPO_RAW"
fi

# ---- 3) Models (โหลดเบื้องหลัง ComfyUI เปิดได้เลย) ---------------------------
HF=https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main
case "${H3_QUANT:-int8}" in
  fp8)  REF2VA=minimax_h3_ref2va_pruned_fp8_scaled.safetensors
        FL2VA=minimax_h3_fl2va_pruned_fp8_scaled.safetensors ;;
  bf16) REF2VA=minimax_h3_ref2va_pruned_bf16.safetensors
        FL2VA=minimax_h3_fl2va_pruned_bf16.safetensors ;;
  *)    REF2VA=minimax_h3_ref2va_pruned_int8_convrot.safetensors
        FL2VA=minimax_h3_fl2va_pruned_int8_convrot.safetensors ;;
esac

# "URL|โฟลเดอร์"
LIST=(
  "$HF/diffusion_models/$REF2VA|diffusion_models"
  "$HF/text_encoders/qwen3vl_32b_minimax_h3_int8_convrot.safetensors|text_encoders"
  "$HF/vae/minimax_h3_video_vae_fp16.safetensors|vae"
  "$HF/vae/minimax_h3_audio_vae_fp32.safetensors|vae"
  "$HF/loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors|loras"
)
if [ "${H3_FL2VA:-0}" = "1" ]; then
  LIST+=("$HF/diffusion_models/$FL2VA|diffusion_models"
         "$HF/loras/minimax_h3_fl2v_turbo_4step_v1.0_768p_comfyui_bf16.safetensors|loras")
fi
for u in ${EXTRA_LORAS:-}; do LIST+=("$u|loras"); done

# Civitai: URL ไม่มีชื่อไฟล์ เลยต้องระบุชื่อเองเป็น versionId:ชื่อไฟล์
CIVITAI_BASE="${CIVITAI_BASE:-https://civitai.red}"
add_civitai() {
  local sub="$1"; shift
  for item in "$@"; do
    local vid="${item%%:*}" name="${item#*:}"
    if [ "$vid" = "$item" ] || [ -z "$name" ]; then
      echo "⚠️  รูปแบบผิด (ต้องเป็น versionId:ชื่อไฟล์): $item"; continue
    fi
    LIST+=("$CIVITAI_BASE/api/download/models/$vid|$sub|$name")
  done
}
add_civitai loras ${CIVITAI_LORAS:-}
add_civitai diffusion_models ${CIVITAI_MODELS:-}

download() {
  local url="$1" sub="$2"
  local name="${3:-$(basename "${url%%\?*}")}"
  local out="$MODELS/$sub/$name"
  if [ -f "$out" ]; then echo "⏭️  มีแล้ว: $sub/$name"; return 0; fi
  # token ส่งทาง header เท่านั้น จะได้ไม่หลุดลง log
  local auth=()
  case "$url" in
    *civitai*)     [ -n "${CIVITAI_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $CIVITAI_TOKEN") ;;
    *huggingface*) [ -n "${HF_TOKEN:-}" ]      && auth=(-H "Authorization: Bearer $HF_TOKEN") ;;
  esac
  echo "⬇️  $sub/$name"
  for try in 1 2 3 4 5; do
    if curl -fL --retry 3 -C - "${auth[@]}" -o "$out.part" "$url" -s -S; then
      mv "$out.part" "$out"; echo "✅ $sub/$name"; return 0
    fi
    echo "⚠️  retry $try: $name"; sleep $((try*5))
  done
  echo "❌ ดาวน์โหลดไม่สำเร็จ: $url"
}

(
  for item in "${LIST[@]}"; do
    IFS='|' read -r url sub name <<< "$item"
    download "$url" "$sub" "$name"
  done
  echo "🎉 โมเดลครบแล้ว — กด R (Refresh) ใน ComfyUI"
  touch "$ROOT/.h3_models_ready"
) &

echo "==== nodes+workflow เสร็จ, โมเดลกำลังโหลดเบื้องหลัง (ดู log: $LOG) ===="
