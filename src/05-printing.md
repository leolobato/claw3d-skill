<!-- MODULE: printing -->

## Printer Setup — Do This First

**On first use**, a printer AND a linked slicing profile are both required. The profile (created from a 3MF) stores the printer's build volume (`build_width` × `build_depth` × `build_height` in mm), which the slicer uses to scale models correctly. Without it, slicing fails.

### What the 3MF carries

When you upload a Cura project file (`.3mf`), the slicer extracts:
- `machine_name` — Printer model (e.g. "Creality K2 Pro")
- `build_width` × `build_depth` × `build_height` — Build volume in mm
- `nozzle_size` — Nozzle diameter in mm
- Full Cura machine + extruder definitions (temperatures, speeds, layer heights, etc.)

### How to export from Cura

> In Cura with your printer loaded: **File → Save → "Export Universal Cura Project"** → save as `.3mf`.

This captures the full printer config, not just the model geometry.

**Printer add flags:**
- `--name` (required): Display name, e.g. `"Creality K2 Pro Living Room"`
- `--host` (required): Printer IP or hostname
- `--port` (required): Moonraker usually 7125; Creality K2 SE often 4408
- **SECURITY:** Moonraker's default config has no authentication. Anyone on the same network can send commands to the printer. Consider enabling Moonraker's API key authentication or restricting access to trusted IPs via firewall rules.
- `--profile-from-3mf` (**required for slicing**): Create and link profile from 3MF in one step. Without this, slicing will fail until a profile is linked manually via `printer set-profile`.
- `--id` (optional): CLI slug. If omitted, derived from `--name` (e.g. `"Creality K2 Pro"` → `creality_k2_pro`)

```bash
claw3d printer add --name "<name>" --host <ip> --port <port> --profile-from-3mf <path> [--id <slug>]
claw3d printer set-profile <printer_id> <profile_id>
claw3d printer set-default <id>   # only needed when 2+ printers; first printer auto-becomes default
claw3d printer remove <id>
```

**Parse user input:** "Creality K2 SE Living Room 192.168.1.100:4408" → name=`"Creality K2 SE Living Room"`, host=`192.168.1.100`, port=`4408`. If user also sends 3MF, add `--profile-from-3mf <path>`.

**Default printer:** The first printer added is automatically set as the default. When there is only one printer, it is always used without asking. When 2+ printers exist and no default is set, ask the user which to use, then run `claw3d printer set-default <id>` with their choice so subsequent operations don't need to ask again.

**No 3MF yet?** Add the printer without it, then immediately ask:
> To complete setup, please send your Cura project file (.3mf). In Cura: **File → Save → "Export Universal Cura Project"**. This gives me your exact build volume and settings.

Then: `claw3d profile create --from-3mf <path> --name "<printer_id>_profile"` → `claw3d printer set-profile <printer_id> <profile_id>`

**Fresh start:** Run `claw3d profile clear`, then re-add printer with `--profile-from-3mf`.

**Printer backends:** Run `claw3d configure backends` to see options. Supported:
- **Moonraker** (Klipper) — default, port 7125
- **PrusaLink** — Prusa printers
- **Bambu Lab (via bambu-gateway)** — P1P, P1S, X1C, A1, A1 Mini via bambu-gateway REST API. Simpler setup: just provide gateway URL + printer serial. See below.

Community can add more backends in `claw3d/backends/`.

### Bambu Lab Printer Setup (via bambu-gateway)

If the user has a Bambu Lab printer, use this setup flow instead of the Moonraker path:

> Let's get your Bambu printer set up. I need:
>
> 1. **Printer name** — e.g. "Bambu X1C Workshop"
> 2. **bambu-gateway URL** — The host:port where bambu-gateway runs (e.g. `10.0.1.50:4844`)
> 3. **Printer serial** — Found on the printer label or Settings → General → Device Info
> 4. **OrcaSlicer/BambuStudio project file (.3mf)** — Export from OrcaSlicer: **File → Export → Export 3MF** (or Save Project As)

```bash
claw3d printer add --name "<name>" --host <gateway_ip> --port <gateway_port> \
  --backend bambu_gateway --printer-serial <serial> --profile-from-3mf <path>
```

**Key differences from Moonraker:**
- `--backend bambu_gateway` is required
- `--printer-serial` identifies which printer on the gateway
- The 3MF should come from **OrcaSlicer or BambuStudio** (not Cura)
- No access codes or MQTT credentials needed — bambu-gateway handles auth internally

### AMS (Automatic Material System) — Bambu Only

```bash
claw3d ams --printer <bambu_id>          # Show loaded filaments + matched profiles
claw3d slice ... --tray N                # Use specific AMS tray's filament
claw3d print --file model.3mf --printer <bambu_id>  # Print 3MF to Bambu
```

## Before Printing

**ALWAYS** run `claw3d printers` before sending a print:
- **0 printers:** Tell user to add a printer first.
- **1 printer:** Use it.
- **2+ printers:** Ask in a numbered list:
  > Which printer should I send the G-code to?
  > 1. [First printer name]
  > 2. [Second printer name]

## Print Commands

```bash
# Moonraker/PrusaLink: G-code
claw3d print --gcode model.gcode [--printer id]

# Bambu Gateway: 3MF (use --file for format-agnostic)
claw3d print --file model.3mf --printer <bambu_id>
claw3d status [--printer id]
claw3d pause [--printer id]
claw3d resume [--printer id]
claw3d cancel [--printer id]
claw3d camera [--printer id] [--snapshot]
claw3d preheat --extruder 200 --bed 60 [--printer id]
claw3d cooldown [--printer id]
claw3d home [--axes x y z] [--printer id]
claw3d files [--path subdir] [--printer id]
claw3d start --file model.gcode [--printer id]
claw3d emergency-stop [--printer id]
claw3d metadata --file model.gcode [--printer id]
```

## Multi-Plate Queue

When a model needs more than one build plate:
1. Slice each plate.
2. `claw3d queue add plate1.gcode --label "Plate 1"`, etc.
3. `claw3d print --gcode plate1.gcode`
4. When user says "print finished" / "next": run `claw3d queue next`, ask to start next.
5. If queue is empty (exit 1): "All plates are done!"

```bash
claw3d queue add model_plate1.gcode --label "Plate 1"
claw3d queue list
claw3d queue next    # pops and returns next path
claw3d queue clear   # clear entire queue
```

## Printer ↔ Profile

Each printer can have a linked default profile. Run `claw3d printer list` to see links including build volume. Use that profile when slicing for that printer.

```
  Creality K2 Pro (creality_k2_pro): 192.168.1.50:4408 [moonraker] [profile: creality_k2_pro_profile] [350×350×350mm] (default)
```

The build volume (`350×350×350mm`) is snapshotted from the profile when it is linked. **When slicing AI-generated or user-provided models** (no dimensions file), read the printer's build volume from `claw3d printer list` and use the smallest dimension as the default `--max-dimension` suggestion, rather than asking the user to guess.

<!-- /MODULE: printing -->
