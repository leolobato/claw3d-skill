# Provider: Meshy (Image-to-3D)

Alternative AI provider for 3D model generation. Uses the Meshy REST API instead of FAL.ai/Rodin.

## When to Use

- User prefers Meshy over FAL/Rodin
- FAL_API_KEY is not configured but MESHY_API_KEY is
- User wants specific Meshy features (low-poly mode, quad topology, PBR maps)

## Prerequisites

- **MESHY_API_KEY** — Get at https://www.meshy.ai/settings/api (format: `msy_...`)
- **Pricing:** Free 200 credits/mo; Pro $10/mo (1k credits); meshy-6 generation = 20 credits + 10 for textures = 30 credits per model

## API Reference

**Base URL:** `https://api.meshy.ai/openapi/v1`
**Auth:** `Authorization: Bearer ${MESHY_API_KEY}`

### Step 1 — Create Task

```bash
curl -X POST https://api.meshy.ai/openapi/v1/image-to-3d \
  -H "Authorization: Bearer ${MESHY_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "image_url": "https://example.com/photo.jpg",
    "ai_model": "meshy-6",
    "should_texture": true,
    "enable_pbr": true,
    "should_remesh": true,
    "target_polycount": 30000,
    "topology": "triangle"
  }'
```

Response: `{"result": "018a210d-8ba4-705c-b111-1f1776f7f578"}`

The `image_url` field accepts a public URL or base64 data URI (jpg/png).

### Step 2 — Poll Until Complete

```bash
curl https://api.meshy.ai/openapi/v1/image-to-3d/<TASK_ID> \
  -H "Authorization: Bearer ${MESHY_API_KEY}"
```

Task states: `PENDING` → `IN_PROGRESS` → `SUCCEEDED` / `FAILED` / `CANCELED`

Poll every 5 seconds. Typical generation time: 1-3 minutes.

### Step 3 — Download Model

On `SUCCEEDED`, the response contains:

```json
{
  "status": "SUCCEEDED",
  "model_urls": {
    "glb": "https://assets.meshy.ai/.../model.glb?Expires=...",
    "fbx": "https://assets.meshy.ai/.../model.fbx?Expires=...",
    "obj": "https://assets.meshy.ai/.../model.obj?Expires=...",
    "usdz": "https://assets.meshy.ai/.../model.usdz?Expires=..."
  },
  "thumbnail_url": "https://assets.meshy.ai/.../preview.png?Expires=..."
}
```

Download the GLB URL to the workspace. Asset URLs are signed and expire after 3 days.

**No native STL output.** Convert from GLB using trimesh:

```python
import trimesh
mesh = trimesh.load('model.glb', force='mesh')
mesh.export('model.stl')
```

## Create Task Parameters

| Parameter | Default | Description |
|---|---|---|
| `image_url` | required | Public URL or base64 data URI |
| `ai_model` | `"latest"` | `"meshy-5"`, `"meshy-6"`, or `"latest"` |
| `model_type` | `"standard"` | `"standard"` or `"lowpoly"` |
| `topology` | `"triangle"` | `"quad"` or `"triangle"` |
| `target_polycount` | 30000 | Range: 100-300,000 |
| `should_texture` | `true` | Generate texture maps (+10 credits) |
| `enable_pbr` | `false` | Add metallic/roughness/normal maps |
| `should_remesh` | `false` | Topology/polycount optimization |
| `texture_prompt` | — | Up to 600 chars guiding texture style |
| `symmetry_mode` | `"auto"` | `"off"`, `"auto"`, `"on"` |
| `pose_mode` | `""` | `"a-pose"`, `"t-pose"`, or `""` |

## Multi-Image Generation

For better quality with multiple viewpoints:

```bash
curl -X POST https://api.meshy.ai/openapi/v1/multi-image-to-3d \
  -H "Authorization: Bearer ${MESHY_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "image_urls": [
      "https://example.com/front.jpg",
      "https://example.com/side.jpg",
      "https://example.com/back.jpg"
    ],
    "ai_model": "meshy-6"
  }'
```

Accepts 1-4 images. Same polling and download pattern.

## Integration with claw3d

To use Meshy instead of FAL.ai as the generation backend:

```bash
claw3d configure provider --set meshy
claw3d convert --image <MediaPath> --output model_<ID>.glb
```

The `claw3d convert` command routes to Meshy's API when configured. The workflow (convert → preview → send) remains identical — only the backend changes.

## Rate Limits

| Tier | Requests/sec | Concurrent tasks |
|---|---|---|
| Pro | 20 | 10 |
| Studio | 20 | 20 |
| Enterprise | 100 | 50 |

## Error Handling

| Error | Action |
|---|---|
| 401 Unauthorized | Check MESHY_API_KEY |
| 402 Insufficient credits | Upgrade plan or wait for monthly reset |
| 429 RateLimitExceeded | Reduce request frequency |
| 429 NoMoreConcurrentTasks | Wait for queued tasks to complete |
| Task FAILED | Check `task_error.message` in poll response |

## References

- [Meshy API Docs](https://docs.meshy.ai/en/api/image-to-3d)
- [Meshy Quickstart](https://docs.meshy.ai/en/api/quick-start)
- No official Python SDK — use `requests` or `httpx` directly
