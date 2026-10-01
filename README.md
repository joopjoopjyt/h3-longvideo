# H3 Long Video · Multi-Ref (RunPod)

Workflow ทำวิดีโอยาวด้วย MiniMax H3 (Ref2VA) + ref หลายรูป ต่อคลิปทีละ 5–15 วิ ด้วย ComfyUI_MiniMax_H3_Extender
ตอน deploy จะติดตั้ง node + workflow + ดาวน์โหลดโมเดลให้อัตโนมัติ

## ไฟล์
- `provision.sh` — สคริปต์รันตอน pod บูต
- `workflows/H3_LongVideo_MultiRef.json` — workflow ของเรา (ตัดมาจากตัวอย่างของ Extender เหลือแค่ Ref2VA + Turbo 4-step)

## โมเดลที่โหลด (ค่าเริ่มต้น int8 ≈ 56 GB)
| ไฟล์ | โฟลเดอร์ | ขนาด |
|---|---|---|
| minimax_h3_ref2va_pruned_int8_convrot | diffusion_models | 21 GB |
| qwen3vl_32b_minimax_h3_int8_convrot | text_encoders | 27 GB |
| minimax_h3_video_vae_fp16 | vae | 5.2 GB |
| minimax_h3_audio_vae_fp32 | vae | 0.6 GB |
| minimax_h3_ref2v_turbo_4step_v0.1 (LoRA) | loras | 2 GB |

## ตั้งค่า
1. สร้าง GitHub repo (public) เช่น `h3-longvideo` แล้วอัปโหลดไฟล์ทั้งหมดนี้
2. RunPod → Templates → New Template
   - **Container Image:** `hearmeman/comfyui-minimax-template:v4`
   - **Container Start Command:**
     ```
     bash -c "curl -fsSL https://raw.githubusercontent.com/<USER>/h3-longvideo/main/provision.sh | bash; exec /start_script.sh"
     ```
   - **Expose HTTP Ports:** `8188,8888`
   - **Container Disk:** 40 GB
   - **Environment Variables:**
     - `REPO_RAW` = `https://raw.githubusercontent.com/<USER>/h3-longvideo/main`
     - `download_minimax_h3` = `false` (ไม่ให้ Hearmeman โหลดโมเดลชุดใหญ่ซ้ำ)
     - (ไม่บังคับ) `H3_QUANT` = `int8` / `fp8` / `bf16`
     - (ไม่บังคับ) `H3_FL2VA` = `1` ถ้าจะใช้โหมด first/last frame ด้วย
     - (ไม่บังคับ) `EXTRA_LORAS` = URL LoRA เพิ่ม คั่นด้วยช่องว่าง
3. Deploy: GPU 80 GB (A100/H100) + **Network Volume ≥ 100 GB** (โหลดครั้งเดียว ครั้งต่อไปข้าม)
   เลือก datacenter นอก US / EU / UK / เกาหลีใต้ (เงื่อนไข license ของ H3)

## ใช้งาน
1. เปิดพอร์ต 8188 → Workflows → `H3_LongVideo_MultiRef`
2. รอโมเดลโหลดเสร็จ (ดู `/workspace/h3_provision.log` ใน Jupyter) แล้วกด **R** รีเฟรช
3. ในโหนด Extender: ใส่รูป ref (สูงสุด 9 รูป) → เขียน prompt ใช้ `<Picture 1>`, `<Picture 2>` …
   ขึ้นต้นทุกคลิปด้วยบล็อก `subject_definitions` เพื่อให้ตัวละครคงเดิม
4. `clip_by_clip`: Generate → ดู → ถ้าโอเคติ๊ก Validated → เพิ่มคลิปถัดไป
   หรือเปลี่ยนเป็น `full_batch` เพื่อรันทุกคลิปรวดเดียว
5. ไฟล์วิดีโอสุดท้ายอยู่ที่ `/workspace/ComfyUI/output`
