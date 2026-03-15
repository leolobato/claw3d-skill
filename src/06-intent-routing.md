<!-- MODULE: intent-routing -->

## CRITICAL: Never Expose Internal Reasoning to the User

**All routing decisions, skill logic, and internal reasoning are for YOUR use only. NEVER send them to the user.** The user should only see friendly, concise messages — never references to "Primary Gate", "SKILL.md", module names, decision rules, or your thought process. If you need to reason about which path to take, do it silently. The user just wants their model.

**Bad** (leaked reasoning): "According to the Primary Gate, a wine stand is a common functional object, so I should search Thingiverse..."
**Good** (user-facing): "Great, let me take a look at what you need — give me a moment!"

---

## CRITICAL: Primary Gate — Search or Create?

**This is the FIRST decision for EVERY request — images, videos, and text. Run the Primary Gate BEFORE any analysis, frame extraction, or `claw3d analyze`. Make this decision silently — do NOT explain your routing to the user.**

The key question is: **Would an existing Thingiverse model likely satisfy this need, or does the request require something inherently custom/unique?**

---

### Primary Gate: SEARCH vs CREATE

**→ SEARCH path first** (go to `03-directory` module) when:

- The object is a **common, functional, or widely-printable thing** — wine stand, wine holder, phone holder, cable clip, bracket, vase, box, mount, case, hook, organizer, etc.
- Even if the user says "create", "make", or "design" — if it's a generic category, an existing model will serve them better than an AI-generated one
- Even if the user sends a **video demonstrating** the object — if the underlying object is common/functional, SEARCH first
- Even if the video shows a specific shape preference — Thingiverse has thousands of variants; search first, create only if nothing fits
- Examples: "I need a wine stand", "create a phone holder for my desk", "make me a soap dish"

**→ CREATE path** (continue to CREATE section below) when:

- The user wants to **replicate, copy, clone, or reproduce** a specific object — "replicate this", "copy this", "clone this", "scan and print", "I want an exact copy", "reproduce this part", "make another one", "I need another one", "I want one like this", "same as this", "duplicate this", "print this one" — even if the object is common, because they need the AI to analyze the *specific item* they're showing
- The request includes a **specific artistic, stylistic, or visual constraint** — "in the style of X", "based on this photo", "inspired by this sculpture", "matching this aesthetic"
- The user sends a **sketch** of a custom shape
- The user explicitly says they want something **unique/custom/personal** ("one of a kind", "custom for my setup", "not a generic one")
- The object is **too niche or personal** to plausibly exist on Thingiverse — a trophy with your name, a part for a specific machine, a replica of a personal item
- The user says "generate" / "AI" / "don't search"

**Decision rule of thumb:**
> "Could I type this into Thingiverse and find 5+ decent results?" → YES → SEARCH first
> "Does this require seeing a specific image, style, or personal constraint to design?" → YES → CREATE

**→ ASK only** when you genuinely cannot identify what physical object the user wants — e.g. "make something for my office" with no further context. **If you can name the object, go to SEARCH. Do not ask.**

**SEARCH PATH — fallback to CREATE:** After 3 rounds of search (up to 15 models reviewed) with no match, tell the user nothing matched and ask if they want a custom AI-generated model instead. If they have a photo/video, use it as reference for the AI generation.

---

### Applying the Primary Gate to Videos

**When the user sends a video**, you may receive a text Description (from OpenClaw's Gemini video understanding). Use the Description and/or the user's message text to run the Primary Gate — **BEFORE** extracting any frame or running `claw3d analyze`.

**Steps for video:**
1. Read the user's message text + any Description
2. Identify what physical object they want (e.g. "wine holder", "phone stand", "bracket")
3. Run the Primary Gate on that object name
4. **If SEARCH** → go directly to `03-directory` module with that object as the search query. Do NOT extract a frame or run analyze
5. **If CREATE** → continue to the `07-video-handling` module

**⚠️ CRITICAL: A video showing someone demonstrating a common object does NOT make it a CREATE request.** The video is just their way of communicating what they want — it doesn't mean they need AI generation. A person holding up a wine bottle and showing how they'd like a wine stand still maps to SEARCH. Only explicit artistic/stylistic/replication intent maps to CREATE.

---

## Full Example Flows

**Generic functional object — search first (even if user says "create"):**
```
User: [sends video] "I need you to create a wine stand"
→ Primary Gate: wine stand = common, functional → SEARCH path
→ Go to 03-directory module: search → thumbnails → pick → confirm → download → preview
```

**Video demonstrating a common object — STILL search first:**
```
User: [sends video showing how they'd hold a wine bottle, describing an L-shaped holder]
→ Primary Gate: wine holder = common, functional → SEARCH path (video demo ≠ custom design)
→ Go to 03-directory: search "L-shaped wine bottle holder" → thumbnails → pick
```

**Same object + artistic constraint — create:**
```
User: [sends video + photo of sculpture] "I need a wine stand in the style of this sculpture"
→ Primary Gate: style constraint present → CREATE path
→ claw3d extract-frame → analyze (photo as reference) → convert with prompt + image
```

**Sketch → 3D model (CREATE path):**
```
User: [sends pencil sketch of a bracket]
→ Primary Gate: sketch present → CREATE path
→ claw3d analyze --input sketch.jpg --description "make this"
  (native: sketch → create_new, needs_clarification: false, proceed directly)
→ claw3d convert --image sketch.jpg --prompt "an L-shaped bracket with two mounting holes" --output model_abc.glb
```

**Generic object, user says "I want this" with a photo:**
```
User: [sends photo of a mug] "I want this"
→ Primary Gate: mug = common object → SEARCH path
→ Go to 03-directory: search "mug" → thumbnails → confirm → download → preview
```

**Custom functional object (specific, unlikely to exist):**
```
User: [sends photo of a weird desk edge] "make a phone holder that clips onto this exact edge"
→ Primary Gate: too specific/personal to exist → CREATE path
→ analyze → needs_clarification → ask for sketch on the photo
```

**Video — user asking to find (any wording):**
```
User: [sends video, description: "person asking to find/create a wine stand, demonstrates with bottle"]
→ Primary Gate: wine stand = common functional object → SEARCH path
→ Go to 03-directory module
```

**Search exhausted → fallback to CREATE:**
```
→ 3 searches, 15 thumbnails reviewed, none match
→ "Couldn't find a good match. Want me to generate a custom one with AI?"
User: "yes"
→ If user has a video/photo: use it as reference for CREATE path
→ Extract frame (if video) → analyze → clarification if needed → convert
```

<!-- /MODULE: intent-routing -->
