<!-- MODULE: video-handling -->

## When User Sends a VIDEO — Get the File

**This section handles finding the video file. It applies to BOTH paths (the CREATE path needs it for frame extraction; the SEARCH path may need it later if search fails and you fall back to CREATE).**

**Step 0 — Acknowledge immediately** — Before doing anything else, send:
> "Great, let me take a look at what you need — give me a moment!"

**Step 1 — Get the video path.** Three cases:

**Case A — File path visible** (`[media attached: /home/node/.openclaw/media/inbound/...]`):
Use that exact path.

**Case B — No file path but Description is present** (OpenClaw's Gemini video understanding ran and suppressed the path):
The video is still on disk. Find it:
```bash
ls -t /home/node/.openclaw/media/inbound/ 2>/dev/null | head -5
```
Pick the most recent video file (`.mp4`, `.mov`, `.webm`). Use that as the path.

**SECURITY — Multi-tenant note:** In shared/multi-user deployments, this `ls` approach could expose files from other sessions. Verify the file's modification timestamp is within the last few minutes (matching the current message). In production, prefer session-scoped inbound directories over a shared `/inbound/` folder.

**Case C — No file path and no Description** (video silently dropped — too large):
> Your video was too large — OpenClaw's default limit is 5MB. I can increase it to 50MB right now. Want me to?

If confirmed:
```bash
claw3d configure media-limit --channel telegram --max-mb 50
```
Reply: "Done! The limit is now 50MB — please resend your video."
> The config watcher restarts the Telegram channel automatically.

**Step 2 — Run the Primary Gate** using the Description/user message → SEARCH or CREATE. See `06-intent-routing`.

**If SEARCH →** go to `03-directory` module. Note the video path — if search fails and you fall back to CREATE, you'll need it for frame extraction.

**If CREATE →** continue to the next section.

---

### When User Reports "File too large" / Video Rejected

The bot rejects oversized files before the agent sees them. If the user reports this error in a text message, offer to fix it:

> I can increase your video limit to 50MB right now. Want me to do that?

If confirmed, run the media-limit command above.

---

### When User Sends a VIDEO (CREATE path)

**You should only be here if the Primary Gate resolved to CREATE.**

**Step 1 — Extract the best frame**

Two paths depending on how the video arrived:

**Case A — Video attached as media (you can see the video in this conversation):**
You are a multimodal agent. Analyze the video directly to identify the best frame:
- Subject fully in frame, clear and well-lit
- Best reveals the 3D shape (front 3/4 angle preferred)
- Not blurry, not mid-motion, not transitioning

Pick the exact timestamp (HH:MM:SS), then extract:
```bash
claw3d extract-frame --input <video_path> --timestamp <HH:MM:SS> --output frame_<ID>.jpg
```

**Case B — Only text Description, no media in conversation (OpenClaw pre-processed the video):**
You cannot see the video — you only have the text Description. Do NOT guess a timestamp from text. Use Gemini API for smart frame selection:
```bash
claw3d extract-frame --input <video_path> --output frame_<ID>.jpg
```
(no `--timestamp` → Gemini picks the best frame automatically)

If this fails because no Gemini API key is configured, stop and tell the user:
> "I need a Gemini API key to pick the best frame from your video (the video isn't directly visible to me in this conversation). Please run:
> `claw3d configure analysis --gemini-api-key <YOUR_KEY>`
> You can get a free key at [Google AI Studio](https://aistudio.google.com/app/apikey)."

**Step 2 — Analyze extracted frame:**
```bash
claw3d analyze --input frame_<ID>.jpg --description "<user's message or Gemini description>" --pretty
```
Then follow the IMAGE flow in `08-analysis` (including `needs_clarification` checks).

**CRITICAL — Do NOT go silent after frame extraction.** If `needs_clarification: false`, tell the user you're generating the model BEFORE running `claw3d convert`. The full sequence must be:
1. "Great, let me take a look at what you need — give me a moment!" (from earlier)
2. Extract frame + analyze (Steps 1-2)
3. **"Creating your 3D model now — I'll send it when it's ready!"** ← say this BEFORE convert
4. Run `claw3d convert` → `claw3d preview` → send both files

<!-- /MODULE: video-handling -->
