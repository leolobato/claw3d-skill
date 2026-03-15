# Backend: Blender MCP (AI-Powered 3D Modeling)

Full 3D modeling, sculpting, mesh repair, and export via Blender controlled by Claude through MCP.

## When to Use

- User needs parametric CAD-style modeling (not just image-to-3D)
- Complex mesh operations: boolean union/difference, modifiers, sculpting
- Repair scans using Blender's 3D Print Toolbox
- Create models from scratch with precise dimensions
- User says "model this in Blender", "design a bracket", "create a parametric part"

## Prerequisites

- **Blender 3.6+** — `brew install --cask blender` (macOS) or https://blender.org/download
- **uv** — `brew install uv` (Python package runner)
- Blender GUI must be running (required for the main MCP server)

## Installation

### Step 1 — Configure MCP Server

Add to Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "blender": {
      "command": "uvx",
      "args": ["blender-mcp"]
    }
  }
}
```

For Claude Code, add to `.claude/settings.json` or project MCP config.

### Step 2 — Install Blender Addon

1. Download `addon.py` from https://github.com/ahujasid/blender-mcp
2. Blender > Edit > Preferences > Add-ons > Install > select `addon.py`
3. Enable "Interface: Blender MCP"
4. In 3D View sidebar (N-panel) > BlenderMCP tab > click "Connect to Claude"

### Step 3 — Restart Claude

Restart Claude Desktop or Claude Code to pick up the new MCP server.

## Connection Architecture

```
Claude (MCP client)
    | stdio
uvx blender-mcp  (MCP server process)
    | TCP socket localhost:9876
Blender (with addon running)
```

Port is configurable via `BLENDER_PORT` env var. Remote Blender instances supported via `BLENDER_HOST`.

## Available Tools (17 Named)

| Tool | Purpose |
|---|---|
| `get_scene_info` | Full scene state: objects, camera, render settings |
| `get_object_info` | Details on a named object |
| `get_viewport_screenshot` | Capture current 3D viewport as image |
| `execute_blender_code` | Run arbitrary Blender Python (`bpy`) — the power tool |
| `search_polyhaven_assets` | Find models, textures, HDRIs from PolyHaven |
| `download_polyhaven_asset` | Import PolyHaven asset into scene |
| `set_texture` | Apply texture to object |
| `generate_hyper3d_model_via_text` | Text-to-3D via Rodin (built-in) |
| `generate_hyper3d_model_via_images` | Image-to-3D via Rodin (built-in) |
| `poll_rodin_job_status` | Monitor AI generation job |
| `import_generated_asset` | Import completed AI model |
| `search_sketchfab_models` | Find models on Sketchfab |
| `download_sketchfab_model` | Import Sketchfab model |

**The key tool is `execute_blender_code`** — it gives Claude full access to the Blender Python API (`bpy`). Any operation scriptable in Blender can be done through this tool.

**SECURITY WARNING:** `execute_blender_code` runs arbitrary Python on the Blender host machine. In deployments where untrusted users interact with the agent, Blender should run in a sandboxed environment (container or VM) with no access to sensitive data or network resources. Never expose the Blender MCP socket (port 9876) beyond localhost.

## Common Operations for 3D Printing

### Create Primitives

```python
import bpy
bpy.ops.mesh.primitive_cube_add(size=20, location=(0, 0, 10))
bpy.ops.mesh.primitive_cylinder_add(radius=5, depth=30, location=(30, 0, 15))
```

### Boolean Operations (Union, Difference, Intersection)

```python
import bpy

# Select the target object
body = bpy.data.objects['Body']
cutout = bpy.data.objects['Cutout']

# Add boolean modifier
mod = body.modifiers.new(name='Cut', type='BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = cutout

# Apply modifier
bpy.context.view_layer.objects.active = body
bpy.ops.object.modifier_apply(modifier='Cut')

# Delete the cutter object
bpy.data.objects.remove(cutout, do_unlink=True)
```

### Mesh Repair (3D Print Toolbox)

```python
import bpy

# Select the mesh
obj = bpy.data.objects['ScanMesh']
bpy.context.view_layer.objects.active = obj
obj.select_set(True)

# Enter edit mode for repair
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')

# Fix non-manifold
bpy.ops.mesh.print3d_clean_non_manifold()

# Fill holes
bpy.ops.mesh.fill_holes(sides=0)

# Recalculate normals
bpy.ops.mesh.normals_make_consistent(inside=False)

bpy.ops.object.mode_set(mode='OBJECT')
```

### Modifiers (Remesh, Decimate, Solidify)

```python
import bpy

obj = bpy.data.objects['Model']

# Remesh (voxel-based, creates clean topology)
mod = obj.modifiers.new(name='Remesh', type='REMESH')
mod.mode = 'VOXEL'
mod.voxel_size = 0.5  # mm

# Decimate (reduce polygon count)
mod = obj.modifiers.new(name='Decimate', type='DECIMATE')
mod.ratio = 0.5  # keep 50% of faces

# Solidify (add thickness to thin surfaces)
mod = obj.modifiers.new(name='Solidify', type='SOLIDIFY')
mod.thickness = 2.0  # mm

# Apply all modifiers
bpy.context.view_layer.objects.active = obj
for mod in obj.modifiers:
    bpy.ops.object.modifier_apply(modifier=mod.name)
```

### Export STL

```python
import bpy

bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.stl_export(
    filepath='/path/to/output/model.stl',
    export_selected_objects=True,
    ascii_format=False,
    apply_modifiers=True
)
```

### Export Other Formats

```python
# GLB
bpy.ops.export_scene.gltf(filepath='/output/model.glb', export_format='GLB')

# OBJ
bpy.ops.wm.obj_export(filepath='/output/model.obj')

# FBX
bpy.ops.export_scene.fbx(filepath='/output/model.fbx')
```

## Integration with claw3d

Blender MCP is a **companion tool**, not a replacement for `claw3d convert`. Use it when:

1. `claw3d convert` (FAL/Rodin) produces a model that needs editing beyond simple rotation
2. User needs precise parametric modeling (exact dimensions, mounting holes, tolerances)
3. Scan repair is too complex for admesh/trimesh
4. User wants to combine multiple models (boolean ops)

**Workflow:** Blender MCP (model/repair) → export STL → `claw3d slice` → `claw3d print`

## Headless Alternative

The main Blender MCP requires the GUI. For headless/automated pipelines:

- **Codex Blender MCP** (`npx -y hassledzebra-codex_blender_mcp`) — launches `blender -b` per call, early stage
- **Direct scripting:** `blender --background --python repair_script.py` — no MCP needed, just shell scripts

## References

- [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp) — 16k+ stars, MIT license
- [blender-mcp.com](https://blender-mcp.com/)
- [Blender 3D Print Toolbox](https://docs.blender.org/manual/en/4.0/addons/mesh/3d_print_toolbox.html)
- [poly-mcp/Blender-MCP-Server](https://github.com/poly-mcp/Blender-MCP-Server) — alternative with 51 named tools, HTTP API
