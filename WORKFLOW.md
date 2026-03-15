# OpenClaw 3D — Complete System Workflow

## System Architecture

```
User (Telegram/Discord/Web)
    │
    ▼
┌──────────────────────┐
│  OpenClaw Gateway     │  Node.js — routes messages, manages sessions
│  (openclaw-base)      │  Mounts: ~/.openclaw → /home/node/.openclaw
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  AI Agent (LLM)       │  Gemini / Claude — runs SKILL.md instructions
│  + claw3d CLI tools   │  Python CLI installed in same container
└──────────┬───────────┘
           │
     ┌─────┴──────────────────────┐
     ▼                            ▼
┌──────────────┐    ┌──────────────────────┐
│ Slicer API    │    │ External APIs         │
│ (CuraEngine)  │    │ - FAL.ai (FLUX/Tripo) │
│ FastAPI        │    │ - Gemini (analysis)   │
│ localhost:8000 │    │ - Thingiverse         │
└──────────────┘    └──────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              ┌──────────┐       ┌──────────┐
              │ Printer 1 │       │ Printer N │
              │ Moonraker │       │ PrusaLink │
              └──────────┘       └──────────┘
```

## File Lifecycle & Naming

All files live in the agent's working directory (Docker: `/home/node/.openclaw/workspace/`).

```
model_<ID>.glb                  ← 3D model (Z-up, preview-ready)
model_<ID>.stl                  ← STL sidecar (Z-up, slicing-ready, original scale)
model_<ID>.stl.dimensions.json  ← {x, y, z, max} in mm
model_<ID>.glb.dimensions.json  ← same, for GLB
model_<ID>.source.json          ← provenance: {source: "thingiverse"|"ai", ...}
preview_<ID>.mp4                ← 360° turntable video
model_<ID>.gcode                ← sliced G-code
model_<ID>_gcode_preview.mp4   ← G-code visualization (body=red, supports=yellow)
model_<ID>_parts/               ← multi-part directory (from Thingiverse)
model_<ID>_x4.stl              ← packed N copies
model_<ID>_plate1.stl          ← multi-plate packing output
thumb_<thing_id>.jpg            ← Thingiverse thumbnail
thumb_<thing_id>_A.jpg          ← stamped thumbnail (option badge)
frame_<ID>.jpg                  ← extracted video frame
```

`<ID>` = first 8 chars of UUID from MediaPath, or thing_id for Thingiverse models.

---

## Master Workflow

```
USER MESSAGE
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     1. ENTRY POINT                              │
│                                                                 │
│  What did the user send?                                        │
│  ├─ Text only (no media) ──────────────────────────► [2]        │
│  ├─ Image (photo/sketch) ──────────────────────────► [3]        │
│  ├─ Video ─────────────────────────────────────────► [4]        │
│  ├─ GLB file ──────────────────────────────────────► [5]        │
│  ├─ 3MF file ──────────────────────────────────────► [6]        │
│  └─ G-code file ───────────────────────────────────► [20]       │
└─────────────────────────────────────────────────────────────────┘
```

---

### [2] TEXT ONLY — Intent Classification

```
USER TEXT
    │
    ├─ Printer setup request ──────────────────────────► [6]
    │   ("add printer", "setup", sends IP/port)
    │
    ├─ Print control ──────────────────────────────────► [20]
    │   ("pause", "resume", "cancel", "status",
    │    "preheat", "home", "camera")
    │
    ├─ Rotation request ───────────────────────────────► [15]
    │   ("rotate 90 on X", "flip it", "turn sideways")
    │
    ├─ Slice settings change ──────────────────────────► [16]
    │   ("make it stronger", "more detail", "20% infill")
    │
    ├─ Re-slice / re-print ────────────────────────────► [14] or [20]
    │   ("slice it again", "print it")
    │
    ├─ Multiple copies ────────────────────────────────► [17]
    │   ("print 4 copies", "fill the plate")
    │
    ├─ Edit existing model ────────────────────────────► [5]
    │   ("make it blue", "add wheels") + prior GLB
    │
    ├─ Object request (identifiable) ──────────────────► [7] PRIMARY GATE
    │   ("I need a wine stand", "make me a phone holder")
    │
    └─ Ambiguous ──────────────────────────────────────► ASK
        ("make something for my office")
```

---

### [3] IMAGE RECEIVED — Primary Gate

```
IMAGE + optional text
    │
    ▼
┌──────────────────────────────────────────────┐
│  [7] PRIMARY GATE: SEARCH or CREATE?         │
│                                              │
│  Replicate/copy intent?                      │
│  ("copy this", "make another one",           │
│   "clone this", "I want one like this")      │
│  ├─ YES ─────────────────────────► [9]       │
│  │   (image IS the design reference)         │
│  │                                           │
│  Could Thingiverse have 5+ results?          │
│  ("phone holder", "vase", "hook")            │
│  ├─ YES ─────────────────────────► [10]      │
│  │   SEARCH PATH                             │
│  │                                           │
│  Artistic/custom/sketch/unique?              │
│  ("style of this sculpture", sketch,         │
│   "custom for my setup")                     │
│  └─ YES ─────────────────────────► [8]       │
│      CREATE PATH                             │
└──────────────────────────────────────────────┘
```

---

### [4] VIDEO RECEIVED — Frame Extraction

```
VIDEO + optional text
    │
    ▼
ACK: "Great, let me take a look — give me a moment!"
    │
    ▼
┌──────────────────────────────────────────────┐
│  Can you SEE the video (media attached)?     │
│  ├─ YES (Case A) ────────────────────┐       │
│  │   Watch video natively.           │       │
│  │   Pick best frame timestamp.      │       │
│  │   ▼                               │       │
│  │   claw3d extract-frame            │       │
│  │     --input <video>               │       │
│  │     --timestamp HH:MM:SS          │       │
│  │     --output frame_<ID>.jpg       │       │
│  │                                   │       │
│  └─ NO (Case B: text Description)────┤       │
│      Video pre-processed by OpenClaw.│       │
│      Find video file:                │       │
│      ls -t inbound/ | head -5        │       │
│      ▼                               │       │
│      claw3d extract-frame            │       │
│        --input <video>               │       │
│        --output frame_<ID>.jpg       │       │
│      (Gemini picks frame)            │       │
│                                      │       │
│  Both cases produce: frame_<ID>.jpg  │       │
└──────────────┬───────────────────────┘       │
               │                               │
               ▼                               │
    ┌─ Treat frame as IMAGE ──────► [7] PRIMARY GATE
    │  (same as [3])
```

---

### [5] GLB RECEIVED — Edit Existing Model

```
GLB + user instruction ("make it blue", "add wheels")
    │
    ▼
ACK: "On it! Editing the 3D model. This can take a few minutes."
    │
    ▼
claw3d convert --edit-3d <GLB_path> --prompt "..." --output edited_<ID>.glb
    │
    ▼
claw3d preview --input edited_<ID>.glb --output preview_edited_<ID>.mp4
    │
    ▼
Send preview + GLB to user
    │
    ▼
[13] ASK ABOUT PRINTING (mandatory for AI models)
```

---

### [6] PRINTER SETUP / 3MF RECEIVED

```
3MF file or setup request
    │
    ▼
┌──────────────────────────────────────────┐
│  Has printer been added?                 │
│  ├─ NO ──► Ask for: name, IP, port      │
│  │         + 3MF (Cura project export)   │
│  │         ▼                             │
│  │         claw3d printer add            │
│  │           --name "..."                │
│  │           --host <ip>                 │
│  │           --port <port>               │
│  │           --profile-from-3mf <path>   │
│  │         ▼                             │
│  │         "Printer added! Ready to go." │
│  │                                       │
│  └─ YES, but no profile linked ──────────┤
│       ▼                                  │
│       claw3d profile create              │
│         --from-3mf <path>                │
│         --name "<printer>_profile"       │
│       ▼                                  │
│       claw3d printer set-profile         │
│         <printer_id> <profile_id>        │
│       ▼                                  │
│       "Profile linked! Build volume:     │
│        WxDxH mm. Ready to slice."        │
└──────────────────────────────────────────┘
```

---

### [7] PRIMARY GATE — Decision Point

```
(Already shown in [3] above)

SEARCH ──► [10]
CREATE ──► [8] (analyze) or [9] (replicate)
```

---

### [8] CREATE PATH — Analyze & Generate

```
Image/frame + text
    │
    ▼
claw3d analyze --input <image> [--description "..."] [--pretty]
    │
    ▼
┌──────────────────────────────────────────────────┐
│  Result: native_mode?                            │
│  ├─ true  → Agent does classification            │
│  └─ false → Gemini returned JSON                 │
│                                                  │
│  image_type: sketch | photo | 3d_model | ref     │
│  needs_clarification?                            │
│                                                  │
│  ├─ false (clear subject, enough constraints)    │
│  │   ▼                                           │
│  │   [9] CONVERT                                 │
│  │                                               │
│  ├─ true, ambiguous subject ─────────────────┐   │
│  │   ASK: "I see X and Y. Which to print?"   │   │
│  │   ▼ (user answers)                        │   │
│  │   [9] CONVERT                             │   │
│  │                                           │   │
│  └─ true, functional object needs design ────┤   │
│      Send frame back + ask for red drawing   │   │
│      ▼ (user sends annotated image)          │   │
│      [9] CONVERT (with --annotated-image)    │   │
└──────────────────────────────────────────────────┘
```

---

### [9] CONVERT — Image/Sketch to 3D Model

```
Image + prompt (+ optional annotated image)
    │
    ▼
ACK: "Creating your 3D model now — I'll send it when it's ready!"
    │
    ▼
claw3d convert --image <path> [--annotated-image <path>] --prompt "..." --output model_<ID>.glb
    │
    ▼
claw3d printer list  ← get build volume for preview
    │
    ▼
claw3d preview --input model_<ID>.glb --output preview_<ID>.mp4 [--build-volume WxDxH]
    │
    ▼
Send preview_<ID>.mp4 + model_<ID>.glb to user
    │
    ▼
[13] ASK ABOUT PRINTING (mandatory for AI models)
```

---

### [10] SEARCH PATH — Find on Thingiverse

```
Query (from text or video/image analysis)
    │
    ▼
ACK: "Let me search for that — one moment!"
    │
    ▼
claw3d find "<query>" --max-passing 5
    │
    ├─ Exit 0 (models found) ─────────────────► [11]
    │
    └─ Exit 1 (none fit) ─────────────────────┐
        Round < 3? Refine query, retry ◄──────┘
        Round = 3?
            ▼
        "Couldn't find a match. Want me
         to generate a custom AI model?"
            ├─ YES ──► [9] CREATE
            └─ NO  ──► END
```

---

### [11] SEARCH — Pick & Present Options

```
claw3d find results (1-5 models)
    │
    ▼
Agent views all thumbnails (multimodal)
Picks best 4 matches
    │
    ▼
claw3d stamp-thumbnails --grid (stamps A/B/C/D, composes 2×2 grid)
    │
    ▼
Send 1 message with grid image attached:
  "Here are four options I found:
   A — [name/reason]  B — [name/reason]
   C — [name/reason]  D — [name/reason]
   Reply A, B, C, D, or none."
    │
    ▼
┌────────────────────────────────────────────┐
│  User picks A, B, C, or D ───────► [12]    │
│  User says "none" ───────────────► [10]    │
│  (retry with refined query, up to 3 rounds)│
└────────────────────────────────────────────┘
```

---

### [12] SEARCH — Variant Check & Preview

```
Chosen model (thing_id)
    │
    ▼
claw3d fetch --list-grouped <thing_id>
    │
    ▼
┌───────────────────────────────────────────────────────┐
│  Sub-variants (size/version)?                         │
│  ├─ YES ──► Ask user which size ──► claw3d fetch      │
│  │          --choose "<variant>" -o model_<ID>.glb    │
│  │          ▼                                         │
│  │          claw3d fit-check -i model_<ID>.stl        │
│  │            --apply-rotation                        │
│  │                                                    │
│  ├─ Cosmetic variations?                              │
│  │  Auto-select "<auto_selected>" ──► claw3d fetch    │
│  │          --choose "<keyword>" -o model_<ID>.glb    │
│  │                                                    │
│  ├─ Multi-part? Already packed by find. Skip.         │
│  │                                                    │
│  └─ Single file / complete-set? Already fetched.      │
│     Skip to preview.                                  │
└────────────────────┬──────────────────────────────────┘
                     │
                     ▼
claw3d preview -i model_<ID>.glb -o preview_<ID>.mp4 --real-scale
    │
    ▼
Send preview + dimensions:
  "Here's option [X] — [name]. Print size: X × Y × Z mm.
   Does this look right?"
    │
    ▼
┌────────────────────────────────────────────────────┐
│  User confirms ──────────────────────► [14]        │
│  User says "no, try another" ────────► [11]        │
│    (pick next option or re-search)                 │
│  User says "rotate it" ─────────────► [15]         │
│  User says "scale it" ──────────────► [15b]        │
└────────────────────────────────────────────────────┘
```

---

### [13] ASK ABOUT PRINTING (AI models only)

```
After sending AI-generated model + preview
    │
    ▼
"Want me to slice this for 3D printing? If so, I need:
 1. Max print size — longest dimension? (e.g. 100mm, 150mm)
 2. Strength — how strong? (10%, 25%, 50%, 75%, 100%)
 3. Detail — print quality? (10%, 25%, 50%, 75%, 100%)"
    │
    ▼
┌──────────────────────────────────────────────┐
│  User provides values ───────────► [14]      │
│  User says "no" ─────────────────► END       │
│  User says "rotate first" ───────► [15]      │
│  User says "edit it" ────────────► [5]       │
└──────────────────────────────────────────────┘
```

---

### [14] SLICE

```
Model file + user preferences
    │
    ▼
┌──────────────────────────────────────────────────────┐
│  Source?                                             │
│  ├─ AI-generated (no .source.json or source=ai)     │
│  │   Uses: model_<ID>.glb                            │
│  │   Flags: --max-dimension <user_value>             │
│  │          --strength <N> --quality <N>              │
│  │                                                   │
│  └─ Thingiverse (source.json has source=thingiverse) │
│      Prefer: model_<ID>.stl (if exists)              │
│      Fallback: model_<ID>.glb + --no-mesh-clean      │
│      NO --max-dimension (already at real size)        │
│      Flags: --strength <N> --quality <N>              │
└────────────────────┬─────────────────────────────────┘
                     │
                     ▼
claw3d profile list  ← get profile ID
    │
    ├─ 0 profiles ──► "Need a 3MF first" ──► [6]
    ├─ 1 profile  ──► use it
    └─ 2+ profiles ─► ask or use printer-linked profile
                     │
                     ▼
claw3d slice -i <model> -p <profile_id> -o model_<ID>.gcode
    [--max-dimension N] [--strength N] [--quality N]
    [--no-mesh-clean] [--build-volume WxDxH]
    │
    ▼
POLL: process poll <session> every 10s until "Wrote" or error
    │
    ▼
"Slicing done! Here's the G-code and preview."
Send: model_<ID>.gcode + model_<ID>_gcode_preview.mp4
    │
    ▼
┌──────────────────────────────────────────────────┐
│  User says "print it" ──────────────► [20]       │
│  User says "rotate it" ─────────────► [15]       │
│  User says "make stronger / more detail" ► [16]  │
│  User says "print 4 copies" ────────► [17]       │
└──────────────────────────────────────────────────┘
```

---

### [15] ROTATE

```
User: "rotate 90 on X" / "flip it" / "turn sideways"
    │
    ▼
claw3d rotate -i model_<ID>.glb --rotation-x 90
    │  (BAKED into file — permanent, cumulative)
    │
    ▼
claw3d preview -i model_<ID>.glb -o preview_<ID>_rotated.mp4 [--build-volume WxDxH]
    │  (no rotation flags — file is already rotated)
    │
    ▼
Send preview:
  "Here it is rotated 90° on X — does this look right?"
    │
    ▼
┌──────────────────────────────────────────────┐
│  User confirms ──────────────────► [14]      │
│  User says "rotate more" ────────► [15]      │
│  User says "undo" ───────────────► [15]      │
│    (rotate opposite direction)               │
└──────────────────────────────────────────────┘
```

### [15b] SCALE

```
User: "make it bigger" / "scale to 150mm"
    │
    ▼
claw3d scale -i model_<ID>.glb --max-dimension 150 -o model_<ID>.glb
    │
    ▼
claw3d preview -i model_<ID>.glb -o preview_<ID>_scaled.mp4 [--build-volume WxDxH]
    │
    ▼
Send preview → user confirms → [14]
```

---

### [16] RE-SLICE WITH DIFFERENT SETTINGS

```
User: "make it stronger" / "20% infill" / "thinner layers"
    │
    ▼
Map natural language → CLI flags:
  "stronger"        → --strength 4
  "20% infill"      → --infill-density 20
  "more detail"     → --quality 4
  "0.1mm layers"    → --layer-height 0.1
    │
    ▼
claw3d slice -i <same model> -p <profile_id> -o model_<ID>.gcode
    <new flags> [--build-volume WxDxH]
    │
    ▼
Send updated G-code + preview ──► [14] exit points
```

---

### [17] MULTIPLE COPIES / FILL PLATE

```
User: "print 4 copies" / "fill the plate"
    │
    ▼
claw3d pack -i model_<ID>.stl --copies 4
    [--rotation-x 90] --build <WxDxH>
    -o model_<ID>_x4.stl
    │
    ▼
┌──────────────────────────────────────────────┐
│  All fit on one plate?                       │
│  ├─ YES ──► slice model_<ID>_x4.stl ► [14]  │
│  │                                           │
│  ├─ Multiple plates needed ──────────────┐   │
│  │   plate1.stl, plate2.stl, ...         │   │
│  │   ▼                                   │   │
│  │   Slice each plate                    │   │
│  │   Queue all: claw3d queue add ...     │   │
│  │   ──────────────────────────► [18]    │   │
│  │                                       │   │
│  └─ Doesn't fit (part too large) ────────┤   │
│      "Only N fit per plate. Pack N?"     │   │
│      ▼ (user confirms)                  │   │
│      Retry with fewer copies             │   │
└──────────────────────────────────────────────┘
```

---

### [18] MULTI-PLATE QUEUE

```
Multiple plates sliced and queued
    │
    ▼
claw3d print --gcode plate1.gcode
    │
    ▼
"Plate 1 printing! Let me know when it's done."
    │
    ▼
User: "done" / "next"
    │
    ▼
claw3d queue next
    ├─ Returns next path ──► claw3d print --gcode <path>
    │   "Plate 2 printing!"
    │   ▼
    │   (loop until queue empty)
    │
    └─ Exit 1 (empty) ──► "All plates printed! Assembly time."
```

---

### [20] PRINT CONTROL

```
┌─────────────────────────────────────────────────────────┐
│  claw3d printers  ← check printer availability          │
│  ├─ 0 printers ──► "Add a printer first" ──► [6]       │
│  ├─ 1 printer  ──► use it                              │
│  └─ 2+ printers ─► ask which one                       │
│                                                         │
│  Action?                                                │
│  ├─ PRINT ────► claw3d print --gcode <file> [--printer] │
│  ├─ STATUS ───► claw3d status [--printer]               │
│  ├─ PAUSE ────► claw3d pause [--printer]                │
│  ├─ RESUME ───► claw3d resume [--printer]               │
│  ├─ CANCEL ───► claw3d cancel [--printer]               │
│  ├─ CAMERA ───► claw3d camera [--printer] [--snapshot]  │
│  ├─ PREHEAT ──► claw3d preheat --extruder T --bed T     │
│  ├─ COOLDOWN ─► claw3d cooldown [--printer]             │
│  ├─ HOME ─────► claw3d home [--axes x y z]             │
│  ├─ FILES ────► claw3d files [--path subdir]            │
│  ├─ START ────► claw3d start --file <name>              │
│  └─ STOP ─────► claw3d emergency-stop [--printer]       │
└─────────────────────────────────────────────────────────┘
```

---

## Key Loops & Back-Edges

```
[9]  CONVERT ──► [13] ASK ──► [14] SLICE ──► [20] PRINT
                   │             ▲    │
                   │             │    ├──► [15] ROTATE ──► [14]
                   │             │    ├──► [16] RE-SLICE ──► [14]
                   │             │    └──► [17] COPIES ──► [14]
                   │             │
                   └─ [15] ROTATE (before slicing)
                   └─ [5]  EDIT ──► [13]

[10] SEARCH ──► [11] PICK ──► [12] VARIANT ──► [14] SLICE ──► [20] PRINT
                  ▲                   │
                  └───── user rejects ┘

[10] SEARCH (3 rounds fail) ──► [9] CREATE (fallback)
```

---

## Coordinate System

**Everything is Z-up** except pyrender preview (Y-up, converted at render time).

| Stage | Up | Notes |
|-------|-----|-------|
| Thingiverse STL | Z | Native |
| AI GLB (post-convert) | Z | +90°X baked during `claw3d convert` |
| `claw3d rotate` | Z | Rotates in Z-up space |
| `claw3d pack` | Z | Packs in Z-up space |
| Slicer API | Z | Expects Z-up |
| G-code | Z | Layer height = Z |
| **Preview** | **Y** | −90°X applied at render time only |

---

## State Tracking — What the System Remembers

| State | Where stored | Deterministic? |
|-------|-------------|----------------|
| Model geometry + rotation | In the .glb/.stl file itself | YES — `claw3d rotate` bakes it |
| Model dimensions | .dimensions.json sidecar | YES |
| Model provenance (AI vs Thingiverse) | .source.json sidecar | YES |
| Printer config | ~/.config/claw3d/config.json | YES |
| Slicing profile | Slicer API /profiles registry | YES — but lost on container restart |
| Print queue | ~/.config/claw3d/queue.json | YES |
| **Slice settings (strength, quality)** | **Nowhere — agent memory only** | **NO** |
| **Max print dimension (AI models)** | **Nowhere — agent memory only** | **NO** |
| **User's preferred orientation** | **In the file (after rotate)** | **YES** |
| **Which Thingiverse option was picked** | **Nowhere — agent memory only** | **NO** |
| **Conversation context / intent** | **Agent context window** | **NO** |

---

> **Planned improvements have been moved to [ROADMAP.md](ROADMAP.md).**
