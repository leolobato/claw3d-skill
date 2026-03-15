# Backend: Bambu Lab

Bambu Lab printer support via local MQTT (LAN) or cloud API. Supports P1P, P1S, X1C, A1, A1 Mini.

## Dependencies

- **Python library:** `bambulabs_api` (`pip install bambulabs_api`) — actively maintained, v2.6.6+
- **Connection:** Local network MQTT (port 8883, TLS) — preferred for speed and reliability
- **Alternative:** `bambu-lab-cloud-api` for cloud + local unified access (works without developer mode)

## Setup

### Option A — Local LAN (recommended)

Requires the printer's LAN IP and access code (found in printer settings under Network → LAN Mode).

```bash
claw3d printer add --name "<name>" --host <ip> --port 8883 --backend bambu \
  --access-code <ACCESS_CODE> --serial <SERIAL_NUMBER> \
  --profile-from-3mf <path_to_3mf>
```

**Finding your access code:**
- On the printer: Settings → Network → LAN Mode → Access Code
- Or via Bambu Handy app: Device → Settings → LAN Mode

**Finding your serial number:**
- On the printer: Settings → General → Device Info
- Or on the label on the back/bottom of the printer

### Option B — Cloud API

Uses Bambu Lab cloud account. Works without developer mode but adds latency.

```bash
claw3d printer add --name "<name>" --backend bambu-cloud \
  --bambu-email <email> --bambu-password <password> \
  --profile-from-3mf <path_to_3mf>
```

The CLI discovers printers on your account automatically.

## Firmware Auth Note

Bambu Lab's January 2025 firmware update (01.08.03.00+) introduced command verification. Two paths:

| Mode | Local MQTT | Cloud | Third-party tools |
|---|---|---|---|
| **Developer Mode** | Full unrestricted | Disabled | Works with `bambulabs_api` |
| **Standard Mode** | Needs updated library with signing | Yes | Use `bambu-lab-cloud-api` or updated `bambulabs_api` |

**To enable Developer Mode:** Printer → Settings → General → Developer Mode → Enable.
This gives full local LAN control but disables cloud features (remote monitoring via app, cloud printing).

## Slicing Differences

Bambu Lab printers use **OrcaSlicer** or **BambuStudio** profiles instead of CuraEngine:

- **If user has a Bambu Studio or OrcaSlicer `.3mf`:** Use `--profile-from-3mf` as normal — the slicer extracts build volume and settings
- **If user only has CuraEngine profiles:** The CuraEngine slicer still produces valid G-code, but Bambu-specific features (AMS filament mapping, flow calibration, pressure advance) won't be available
- **For best results with Bambu printers:** Ask user to export from OrcaSlicer instead of Cura

### OrcaSlicer CLI (headless slicing alternative)

For Bambu-specific G-code features, OrcaSlicer CLI can be used instead of CuraEngine:

```bash
# Slice a pre-configured 3MF project
orca-slicer --slice <project.3mf> --export-gcode -o model.gcode

# Export model format
orca-slicer --export-stl <project.3mf>
```

**Caveat:** OrcaSlicer CLI requires a pre-configured 3MF (profiles baked in). It cannot accept a raw STL + profile name like CuraEngine can.

## Print Commands

All standard `claw3d print` commands work with Bambu backend. Additional Bambu-specific commands:

```bash
# AMS filament management
claw3d ams status [--printer id]              # Show AMS tray contents
claw3d ams switch --tray <N> [--printer id]   # Switch active filament tray

# Camera
claw3d camera --snapshot [--printer id]       # Capture still frame
claw3d camera --timelapse [--printer id]      # Download latest timelapse

# LED control
claw3d led --on [--printer id]
claw3d led --off [--printer id]

# Speed profiles
claw3d speed --mode <silent|normal|sport|ludicrous> [--printer id]
```

## File Upload

Bambu printers use FTPS (port 990) for file upload instead of Moonraker's HTTP API:

```bash
claw3d print --gcode model.gcode --printer <bambu_id>
# Internally: uploads via FTPS → triggers print via MQTT
```

The `claw3d print` command handles this transparently — no user-facing difference.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `BAMBU_ACCESS_CODE` | Yes (LAN mode) | Printer access code for local MQTT auth |
| `BAMBU_SERIAL` | Yes (LAN mode) | Printer serial number |
| `BAMBU_EMAIL` | Yes (cloud mode) | Bambu Lab account email |
| `BAMBU_PASSWORD` | Yes (cloud mode) | Bambu Lab account password |

These can be set in `.env` or passed via `claw3d printer add` flags.

## Error Handling

| Error | Action |
|---|---|
| MQTT connection refused | Check IP, access code, and that printer is on same network |
| Auth failed (new firmware) | Enable Developer Mode or update `bambulabs_api` to v2.6+ |
| FTPS upload failed | Check port 990 reachable; some routers block FTP |
| "Printer offline" | Printer may be in sleep mode — wake via physical button or Bambu Handy |
| AMS filament error | Run `claw3d ams status` to check tray state |

## References

- [bambulabs_api](https://github.com/BambuTools/bambulabs_api) — Python library (PyPI: `bambulabs_api`)
- [Bambu-Lab-Cloud-API](https://github.com/coelacant1/Bambu-Lab-Cloud-API) — Cloud + local unified
- [OpenBambuAPI](https://github.com/Doridian/OpenBambuAPI) — MQTT protocol reference
- [schwarztim/bambu-mcp](https://github.com/schwarztim/bambu-mcp) — MCP server for Claude integration
- [OrcaSlicer](https://github.com/SoftFever/OrcaSlicer) — Bambu-compatible slicer with CLI
