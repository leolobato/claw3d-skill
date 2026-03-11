# Module: AI Model Creation

**You CAN convert 2D images to 3D models AND edit existing 3D models (GLB).** When the user sends a GLB and asks to modify it (e.g. "make it blue", "add wheels"), use `claw3d convert --edit-3d <GLB_MediaPath>`. When they send an image, use `--image`.

## When to Use

- **"Modify this 3D model"** / **"Change the color"** / **"Make it blue"** (user sent a GLB) — use `--edit-3d` flow
- "Turn this sketch into a 3D model" / "Make this image a 3D model"
- "Convert this to 3D" / "Create a 3D model from this photo"
- "Could we 3D print this?" (with image) — convert first, then slice and print
- "3D print this image" / "Print this as a 3D"

**Always require an image or sketch.** Do not use text-only `--prompt` for new model creation — results are not accurate enough. If the user asks to "make a cup" without an image, ask them to send a sketch or photo, or offer to search Thingiverse instead.

**CRITICAL — User sent a GLB and wants to edit it:** Run `claw3d convert --edit-3d <GLB_MediaPath> --prompt "..." --output edited_<ID>.glb`. Never say you cannot edit 3D models.

## Acknowledge Before Converting

**When the user asks to create a 3D model from an image OR to edit a 3D model**, REPLY IMMEDIATELY first:
- "Yes! Give me a minute—I'll let you know when the 3D model is ready."
- "On it! I'll work on that now and get back to you when it's done."

Image conversion takes 1–2 minutes. Edit-3d can take 5–10+ minutes when Hunyuan is cold. Do NOT stay silent—always acknowledge first.

## Critical: Image from Chat

When the user attaches an image, the message includes a **MediaPath**. **Always** pass that exact path to `--image`. Copy it character-for-character.

**IMPORTANT — Unique output paths:** Derive a short ID from the MediaPath. Format: `.../file_13---b10560d7-18fd-40e9-8a49-996ad190a26c.jpg` — use first 8 chars after `---` (e.g. `b10560d7`) as `ID`.

**Build volume:** Before running `claw3d preview`, check if a printer is configured with a known build volume: run `claw3d printer list` and look for `[WxDxH mm]` (e.g. `[350×350×350mm]`). If found, pass `--build-volume WxDxH` (e.g. `--build-volume 350x350x350`) — this renders the grey build plate and grid under the model for a realistic preview.

```bash
ID=b10560d7   # from MediaPath
claw3d convert --image <MediaPath> --output model_${ID}.glb
# With printer build volume (preferred):
claw3d preview --input model_${ID}.glb --output preview_${ID}.mp4 --build-volume 350x350x350
# Without printer configured:
claw3d preview --input model_${ID}.glb --output preview_${ID}.mp4
```

If the MediaPath has no UUID (unusual), use `date +%s` for a unique ID. **NEVER** send `model.glb` or `preview.mp4` that existed before this request.

## Edit-3D Workflow (MUST follow in order)

1. **Acknowledge** — "On it! Editing the 3D model. The Hunyuan step can take a few minutes when cold."
2. **Run convert** — `claw3d convert --edit-3d <GLB_MediaPath> --prompt "..." --output edited_<ID>.glb`
3. **Poll convert** — Edit-3D can take 5–10+ minutes. If you see `Command still running`:
   - **Immediately** call `process poll <session>`.
   - If still running → wait 10 seconds → call `process poll <session>` again. Repeat.
   - When you see `Wrote edited_<ID>.glb` → convert is done.
   - **Do NOT stop polling and wait for the user.**
4. **Run preview** — `claw3d preview --input edited_<ID>.glb --output preview_edited_<ID>.mp4`
5. **Poll preview** — same pattern: poll until you see `Wrote`.
6. **Send both files** — You MUST call the `message` tool. **NEVER output MEDIA: as text.**
   ```
   message(action="send", text="Here's the updated preview!", media="preview_edited_<ID>.mp4")
   message(action="send", text="And the edited model:", media="edited_<ID>.glb")
   ```

**NEVER use --image for a GLB** when modifying. --image is for 2D sketches/photos.

## Convert Workflow (image/sketch → 3D)

1. **Acknowledge** — "Yes! Give me a minute—I'll let you know when the 3D model is ready."
2. **Check build volume** — Run `claw3d printer list`; note `[WxDxH mm]` if present.
3. **Run convert** — `claw3d convert --image <MediaPath> --output model_<ID>.glb`
4. **Poll convert** — Convert takes 1–2 minutes. If you see `Command still running`:
   - **Immediately** call `process poll <session>`.
   - If still running → wait 10 seconds → call `process poll <session>` again. Repeat.
   - When you see `Wrote model_<ID>.glb` → convert is done.
   - **Do NOT stop polling and wait for the user to ask. Do NOT return control to the user.**
5. **Run preview** — `claw3d preview --input model_<ID>.glb --output preview_<ID>.mp4 [--build-volume WxDxH]`
6. **Poll preview** — If you see `Command still running`:
   - **Immediately** call `process poll <session>`.
   - If still running → wait 10 seconds → call `process poll <session>` again. Repeat.
   - When you see `Wrote preview_<ID>.mp4` → preview is done.
7. **Send files** — You MUST call the `message` tool to send files. **NEVER output MEDIA: as text — it will NOT deliver the file.**
   ```
   message(action="send", text="Here's your 3D model preview!", media="preview_<ID>.mp4")
   message(action="send", text="And the 3D model file:", media="model_<ID>.glb")
   ```
8. **ALWAYS ask about printing** — After sending the preview and model, ask:
   > Want me to slice this for 3D printing? If so, I need:
   >
   > 1. **Max print size** — What's the longest dimension? (e.g. 100mm, 150mm)
   > 2. **Strength** — How strong? (10%, 25%, 50%, 75%, or 100%)
   > 3. **Detail** — How much print quality? (10%, 25%, 50%, 75%, or 100%)

   This is **mandatory** for AI-generated models — they have no real-world dimensions, so you MUST get the max print size from the user before slicing. Do NOT slice without asking. Do NOT use a default size.

**CRITICAL:** Run convert and preview via exec BEFORE sending. The files do not exist until you create them. You MUST poll both commands to completion — never stop early.

## Commands

```bash
# Image/sketch → 3D
claw3d convert --image <MediaPath> [--prompt "extra description"] --output model_<ID>.glb

# Multiview: 4-quadrant image → Gemini → Hunyuan3D
claw3d convert --image multiview.png --multiview [--prompt "add wheels"] --output model_<ID>.glb

# Edit 3D: modify existing GLB
claw3d convert --edit-3d model.glb --prompt "make it blue" --output edited.glb

# Preview
claw3d preview --input model_<ID>.glb --output preview_<ID>.mp4

# Scale
claw3d scale --input model.glb --output scaled.glb --scale 0.5
```

## Prerequisites

- **FAL_API_KEY** — Required for convert (set in Control UI → Skills → claw3d)
- **Preview** — Headless: xvfb and xauth; or use openclaw:claw3d Docker image

## Error Handling

| Error | Check |
|-------|-------|
| Convert fails | FAL_API_KEY set, image exists, PNG/JPG |
| No image URL in FLUX response | FAL key valid; try again (transient) |
| Preview fails | Headless: apt install xvfb xauth |

**API key errors:** When convert fails with "FAL API key" or "401/403", ask the user to verify their API key in Control UI → Skills → claw3d. Get a key at https://fal.ai/dashboard/keys
