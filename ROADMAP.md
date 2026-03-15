# Improvements — Where Code Should Replace AI Judgment

> Extracted from WORKFLOW.md Part 2. These are planned improvements, not current behavior.

## Priority 1: Critical — Data Loss / Wrong Behavior

### 1.1 Persist Slice Settings in a Sidecar

**Problem:** When the user says "re-slice but stronger", the agent must remember the previous settings (max-dimension, strength, quality, infill, etc.). If the agent forgets or context is compacted, it either uses defaults or asks again.

**Solution:** Create `model_<ID>.slice_config.json` sidecar. Every `claw3d slice` call writes it. Next slice reads it as defaults.

```json
{
  "max_dimension_mm": 150,
  "strength": 3,
  "quality": null,
  "infill_density": null,
  "layer_height": null,
  "profile_id": "creality_k2_pro_abc123",
  "no_mesh_clean": false,
  "build_volume": "350x350x350"
}
```

`claw3d slice` loads this if it exists, applies CLI overrides on top. Agent only needs to pass what changed.

### 1.2 Persist Model Session Context

**Problem:** After a model is created/fetched, the agent needs to remember: source (AI vs Thingiverse), thing_id, original query, user's chosen option (A/B/C), max print size. If context compacts, all lost.

**Solution:** Extend `model_<ID>.source.json` to become a full session file:

```json
{
  "source": "thingiverse",
  "thing_id": "660698",
  "query": "wine stand",
  "option_letter": "B",
  "original_extents_mm": [153.8, 160.5, 69.8],
  "max_dimension_mm": null,
  "created_at": "2026-03-10T14:30:00Z"
}
```

Or for AI models:
```json
{
  "source": "ai",
  "prompt": "a replica of the black S-hook",
  "original_image": "/path/to/frame.jpg",
  "max_dimension_mm": 100,
  "created_at": "2026-03-10T14:30:00Z"
}
```

### 1.3 Profile Persistence Across Restarts

**Problem:** Slicer API stores profiles in memory + disk, but the profile registry (`profiles.json`) lives inside the Docker container at `/opt/claw3d/profiles/`. If the slicer container restarts, profiles MAY survive (volume-mounted) or MAY NOT.

**Solution:**
- Ensure `/opt/claw3d/profiles/` is volume-mounted in docker-compose
- `claw3d printer add --profile-from-3mf` should store the 3MF path in the printer config, so profiles can be auto-recreated on startup
- Add `claw3d profile ensure` command that checks if the linked profile exists and re-creates it from stored 3MF if not

---

## Priority 2: High — Remove AI Guesswork

### 2.1 Deterministic Source-Based Slice Routing

**Problem:** The agent reads skill instructions to decide: "Is this a Thingiverse model? Use --no-mesh-clean and no scaling. Is this AI? Use --max-dimension." This is fragile — the agent can (and has) applied 100mm scaling to Thingiverse models.

**Solution:** Make `claw3d slice` read `.source.json` and auto-configure:

```python
# In slice_cmd.py, after loading the file:
source_json = _load_source_json(inp)
if source_json and source_json.get("source") == "thingiverse":
    # Auto-enable: no scaling, no mesh clean
    if max_dim is None and not parsed.max_dimension:
        max_dim = None  # explicit: no scaling
    if not parsed.no_mesh_clean:
        parsed.no_mesh_clean = True  # auto-protect
```

The agent doesn't need to remember — the file metadata drives it.

### 2.2 `claw3d pipeline` — Single Command for Common Flows

**Problem:** The most common flows (image → 3D → preview → ask about printing) require the agent to orchestrate 3-4 commands in sequence, with correct flag passing between them. Each step is a chance for the agent to make a mistake.

**Solution:** `claw3d pipeline` wraps common multi-step sequences:

```bash
# Image to preview (CREATE path)
claw3d pipeline create --image <path> --prompt "..." --id <ID>
# Does: convert → preview → outputs both files

# Thingiverse to preview (SEARCH path)
claw3d pipeline search "<query>" --pick 3 --id <ID>
# Does: find → stamp thumbnails → output stamped images

# Slice and print
claw3d pipeline print --model <path> --strength 3 --quality 3 --printer <id>
# Does: slice → poll → print → status
```

This reduces agent orchestration errors dramatically.

### 2.3 Deterministic Thumbnail Stamping

**Problem:** The A/B/C badge stamping is a 15-line Python snippet the agent must copy-paste and modify for each thumbnail. Agents regularly botch this (wrong variable, wrong ID, forget to change letter).

**Solution:** Built into CLI:

```bash
claw3d stamp-thumbnails --thumbnails thumb_660698.jpg thumb_123456.jpg thumb_789012.jpg
# Outputs: thumb_660698_A.jpg, thumb_123456_B.jpg, thumb_789012_C.jpg
```

### 2.4 `claw3d suggest-rotation` — Auto-Optimal Print Orientation

**Problem:** The agent guesses print orientation based on visual intuition. Users often need 2-3 rotation cycles to get it right.

**Solution:** Analyze the mesh and suggest the orientation with least overhang / best bed adhesion:

```bash
claw3d suggest-rotation -i model_<ID>.glb --build <WxDxH>
# Output: --rotation-x 90 (flat base detected, 82% bed contact)
```

This could use simple heuristics: find the largest flat face, orient it downward.

---

## Priority 3: Medium — UX & Robustness

### 3.1 Undo/History for Model Edits

**Problem:** `claw3d rotate` overwrites the file. If the user says "undo that rotation", there's no way back except rotating the opposite direction (which accumulates floating-point errors).

**Solution:** Keep a backup before each destructive operation:

```
model_<ID>.glb              ← current
model_<ID>.glb.bak.1        ← before last rotate
model_<ID>.glb.bak.2        ← before that
```

Add `claw3d undo -i model_<ID>.glb` that restores the most recent backup.

### 3.2 Unified Model Status Command

**Problem:** To understand "what has happened to this model", the agent needs to check multiple files: .source.json, .dimensions.json, .slice_config.json, and look for .gcode / preview files.

**Solution:** `claw3d model-status -i model_<ID>.glb`:

```
Model: model_660698.glb
Source: Thingiverse (thing:660698 — "Balancing Wine Holder")
Dimensions: 153.8 × 160.5 × 69.8 mm
Rotation: 90° X (baked)
Sliced: YES → model_660698.gcode (strength 3, quality 3)
Printed: NO
Preview: preview_660698.mp4
```

The agent can call this at the start of a session to recover full context.

### 3.3 Smart Default Max Dimension

**Problem:** For AI models, the agent must ask the user for max print size. But the printer's build volume is known. The agent should suggest a reasonable default.

**Solution:** Already partially there in 05-printing.md, but make it code:

```python
# In slice_cmd.py, for AI models with no --max-dimension:
if source == "ai" and max_dim is None:
    build_vol = get_default_printer_build_volume()
    if build_vol:
        suggested = min(build_vol) * 0.8  # 80% of smallest axis
        print(f"No --max-dimension specified. Suggested: {suggested:.0f}mm "
              f"(80% of printer's {min(build_vol):.0f}mm axis)", file=sys.stderr)
```

### 3.4 Webhook / Event Notifications

**Problem:** Long operations (slice, convert, preview) require the agent to poll. If the agent's context compacts during polling, it loses track.

**Solution:** Add optional webhook callbacks:

```bash
claw3d slice ... --webhook "http://localhost:PORT/callback"
# Slicer calls webhook when done → OpenClaw can notify agent
```

### 3.5 Health Check / Dependency Validation

**Problem:** Multiple services must be running (slicer, printer), multiple API keys configured (FAL, Gemini, Thingiverse). Failures are discovered mid-workflow.

**Solution:** `claw3d doctor`:

```
[OK] Slicer API: http://localhost:8000 (responding)
[OK] FAL_API_KEY: configured
[OK] GEMINI_API_KEY: configured
[OK] THINGIVERSE_ACCESS_TOKEN: configured
[OK] Printer: Creality K2 Pro (192.168.1.100:4408) — online, idle
[OK] Profile: creality_k2_pro_profile (350×350×350mm)
[WARN] ffmpeg: not found (video frame extraction will fail)
```

---

## Priority 4: Structural / DB Improvements

### 4.1 Model Registry (Replace File-Convention DB)

**Problem:** The entire "database" is implicit file naming conventions (`model_<ID>.glb`, `model_<ID>.source.json`, etc.). This is fragile — files can be orphaned, IDs confused, and there's no way to list "all models in this session."

**Solution:** SQLite or JSON registry at `~/.config/claw3d/models.json`:

```json
{
  "models": {
    "660698": {
      "id": "660698",
      "source": "thingiverse",
      "thing_id": 660698,
      "name": "Balancing Wine Holder",
      "files": {
        "glb": "model_660698.glb",
        "stl": "model_660698.stl",
        "gcode": "model_660698.gcode",
        "preview": "preview_660698.mp4",
        "gcode_preview": "model_660698_gcode_preview.mp4"
      },
      "dimensions_mm": [153.8, 160.5, 69.8],
      "slice_config": { "strength": 3, "quality": 3 },
      "rotation_history": ["X+90"],
      "status": "sliced",
      "created_at": "2026-03-10T14:30:00Z",
      "printed_at": null
    }
  }
}
```

Commands:
```bash
claw3d models list              # all models in workspace
claw3d models show <ID>         # full detail
claw3d models clean             # remove orphaned files
```

### 4.2 Session Tracking

**Problem:** No concept of "this conversation's models." If the user starts a new chat, the agent doesn't know what models exist from previous sessions.

**Solution:** Add session_id to model registry. The OpenClaw gateway already has session IDs — pass them through:

```bash
claw3d convert --image ... --session <session_id> --output model_<ID>.glb
```

Then `claw3d models list --session <id>` shows only that session's work.

### 4.3 Print Job Tracking

**Problem:** After `claw3d print`, there's no record of what was printed, when, on which printer, or the outcome. Can't answer "what did I print last week?"

**Solution:** Print history in registry:

```json
{
  "print_history": [
    {
      "model_id": "660698",
      "gcode": "model_660698.gcode",
      "printer_id": "creality_k2_pro",
      "started_at": "2026-03-10T15:00:00Z",
      "status": "completed",
      "duration_minutes": 47
    }
  ]
}
```

### 4.4 Queue Improvements

**Problem:** Queue is a flat list of file paths. No metadata about which model, what plate number, estimated time.

**Solution:** Enrich queue items:

```json
{
  "path": "model_660698_x4_plate1.gcode",
  "label": "Wine Stand × 4 — Plate 1/2",
  "model_id": "660698",
  "plate_number": 1,
  "total_plates": 2,
  "estimated_time_seconds": 2400,
  "estimated_filament_grams": 45.2
}
```

These estimates come from the slicer job status (already available after slicing).

---

## Summary: Top 5 Impact Improvements

| # | Change | Impact | Effort |
|---|--------|--------|--------|
| 1 | **Source-based auto-routing in slice** (2.1) | Eliminates scaling/mesh-clean bugs forever | Low |
| 2 | **Slice config sidecar** (1.1) | Agent never forgets settings on re-slice | Low |
| 3 | **Model registry** (4.1) | Single source of truth, replaces fragile naming | Medium |
| 4 | **`claw3d pipeline`** (2.2) | Reduces 4-step orchestration to 1 command | Medium |
| 5 | **`claw3d doctor`** (3.5) | Catches missing config before user hits errors | Low |
