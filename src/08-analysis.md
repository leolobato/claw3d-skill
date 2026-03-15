<!-- MODULE: analysis -->

## Analysis Modes

Run once per session to understand the configuration:

```bash
claw3d configure analysis --status
```

| Mode | What happens |
|------|-------------|
| `auto` (default) | `claw3d analyze` uses Gemini if key is set, else returns `native_mode: true` |
| `native` | `claw3d analyze` immediately returns `native_mode: true` — you do the analysis |
| `gemini` | `claw3d analyze` uses Gemini; errors if key missing |

---

## CREATE Path: Intent Analysis for Image or Video

**Only enter this section if the Primary Gate resolved to CREATE.**

**Before doing anything with a user's image or video, run `claw3d analyze` (images) or analyze the video natively + `claw3d extract-frame --timestamp` + `claw3d analyze` (videos).**

---

### When User Sends an IMAGE (CREATE path)

**Step 1 — Always run analyze:**

```bash
claw3d analyze --input <MediaPath> [--description "user's message"] [--pretty]
```

**Step 2 — Read the result and branch:**

#### Result has `native_mode: true` → you are the analysis layer

Analyze the image yourself using these rules:

**Classify `image_type`:**
- `sketch`: hand-drawn, pencil/pen outlines, whiteboard drawings → intent is almost always `create_new`, proceed directly
- `photo`: real photograph → read description carefully
- `3d_model`: CAD rendering or existing 3D model screenshot
- `reference`: product photo, inspiration, logo

**Decide `needs_clarification`:**

**OVERRIDE — replicate/copy intent always sets `needs_clarification: false`:**
If the user's message contains any of: "make another one", "copy this", "replicate this", "clone this", "I want one like this", "same as this", "reproduce this", "duplicate this", "print this one" — the photo/frame IS the complete design reference. Proceed directly to convert. Do NOT ask for a drawing. The whole point is that they're showing you the exact object they want.

`false` (proceed without asking) when ALL of these are true:
- Single clear subject identified
- The description or image already specifies at least one key design constraint (size, mounting type, orientation, number of units, etc.)
- Sketches always qualify — the drawing itself conveys the shape intent

`true` (ask ONE clarifying question) when ANY of these:
- Complex scene with multiple objects and no description
- Custom functional or structural object (holder, bracket, stand, organizer, case, clip, mount, etc.) where the description does NOT specify key design details — even if the object is clearly identified — **but only if there is no replicate/copy intent (see override above)**
- Subject is clear but could be made many ways (e.g. "a wine holder" — wall-mount or freestanding? holds 1 bottle or multiple? specific angle?)
- Abstract or landscape photo with no description
- "Make this better" / "improve this" with no context

**Rule of thumb for functional objects:** If you could design it 3+ different ways and the user hasn't said which way → send the frame/image back and ask them to draw on it (see below). **Exception: replicate intent (see override above) → always proceed directly.**

**If `needs_clarification: false`:**

**Step A — Tell the user you're starting** (do NOT stay silent):
> "Creating your 3D model now — I'll send it when it's ready!"

**Step B — Write a `suggested_prompt` and run convert:**
```bash
claw3d convert --image <MediaPath> --prompt "<suggested_prompt>" --output model_<ID>.glb
```

**CRITICAL — When writing `suggested_prompt`:**

**For replicate/copy intent** ("make another one", "copy this", etc.):
Keep it SHORT — one sentence. The image already carries the shape. Do NOT add dimensions, material suggestions, or printing advice.
- ✅ "a replica of the black S-hook, matching its exact shape for hanging kitchen utensils"
- ✅ "a replica of the wooden phone stand shown in the image"
- ❌ "A 3D model of a sturdy S-shaped utility hook, designed for 3D printing, with a flat bar profile and rounded edges. The hook should be approximately 7-8 cm in length..." ← WAY too long, invents dimensions

**For all other intents:**
Describe ONLY the 3D object to be printed. Keep it to 1-2 sentences max. Do NOT include:
- Dimensions or measurements (the image conveys scale)
- Material or printing recommendations (PETG, PLA, etc.)
- Scale references ("sized based on the dog for scale")
- People, hands, or human body parts visible in the image
- Background items, decorations, scene context

Example — user shows a wine bottle next to a dog sculpture:
- ❌ WRONG: "An L-shaped wine holder sized appropriately based on the teal dog sculpture for scale"
- ✅ RIGHT: "An L-shaped wine bottle holder with a circular opening at a 45° angle, wall-mountable"

**If `needs_clarification: true`:**

Two cases:

**Case 1 — Ambiguous subject** (multiple objects, unclear what to print):
Ask ONE specific text question:
> "I see a desk with a laptop and a mug. Which item would you like to 3D print?"

**Case 2 — Subject is clear but it's a photo of a functional/custom object** (holder, bracket, case, mount, stand, organizer, etc.):
1. **Note the original frame path** (e.g. `frame_1a589237.jpg`) — you will need it when the annotated image comes back.
2. Send the extracted frame back to the user and ask them to draw on it in red:
   > "Hey! Could you draw in red on this image to show me the shape you have in mind? Any drawing app works — even a quick scribble on your phone. Then send it back and I'll use it as the design reference."
   Use the `message` tool to attach the frame — do NOT use inline MEDIA: syntax:
   `message(text="Hey! Could you draw...", media="<frame_path>")`
3. Wait for the user to send back the annotated image.

**When the user sends back the annotated image:**
Do NOT say "Yes! On it!" and stop — immediately run exec:
```bash
claw3d convert --image <original_frame_path> --annotated-image <annotated_MediaPath> --prompt "<description of the object, NO scene context>" --output model_<ID>.glb
```
- `<original_frame_path>` = the frame you sent them (e.g. `frame_1a589237.jpg`)
- `<annotated_MediaPath>` = the absolute path from the media attached message
- Then run preview + send both files as usual

---

#### Result has `native_mode: false` (Gemini was used) → act on the JSON

```json
{
  "subject": "a wooden phone stand",
  "image_type": "sketch",
  "intent": "create_new",
  "needs_clarification": false,
  "clarification_question": null,
  "suggested_prompt": "a minimalist wooden phone stand with a 70° angled back support..."
}
```

| `intent` | Action |
|---|---|
| `create_new` | Check `needs_clarification` first — if false, then `claw3d convert --image <MediaPath> --prompt "<suggested_prompt>" --output model_<ID>.glb` |
| `create_attachment` | Same as `create_new` |
| `find_existing` | This shouldn't appear here — Primary Gate should have caught it. But if it does: go to `03-directory` module |

If `needs_clarification: true`:
- **First check for replicate/copy intent in the user's description** — if present ("make another one", "copy this", "replicate", etc.), override to `false` and proceed directly regardless of what Gemini returned.
- Otherwise: send `clarification_question` verbatim (Gemini wrote it to be friendly and specific)
- Do NOT rephrase
- After user replies, re-run: `claw3d analyze --input <MediaPath> --description "<original + reply>"`
- After one round, always proceed

---

## Commands Reference

```bash
# Image intent analysis (outputs JSON)
claw3d analyze --input <image> [--description "text"] [--annotated <image>] [--pretty]

# Video frame extraction
claw3d extract-frame --input <video> [--output frame.jpg] [--timestamp HH:MM:SS]

# Analysis layer configuration
claw3d configure analysis                                 # show status
claw3d configure analysis --mode native                  # use your own AI
claw3d configure analysis --mode auto                    # gemini if available, else native
claw3d configure analysis --mode gemini                  # always use Gemini
claw3d configure analysis --gemini-api-key <KEY>         # set Gemini key
claw3d configure analysis --clear                        # remove Gemini key
```

<!-- /MODULE: analysis -->
