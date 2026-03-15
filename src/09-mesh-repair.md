<!-- MODULE: mesh-repair -->

# Module: Mesh Repair & Format Conversion

**You CAN repair broken 3D scans, fix mesh errors, simplify high-poly models, and convert between 3D formats.** Use `claw3d mesh-repair` for common repairs, or the tools below for specific operations.

## When to Use

- User sends a 3D scan (STL/OBJ/PLY) that has holes, non-manifold edges, or flipped normals
- Slicer rejects a model with mesh errors
- Model has too many polygons for efficient slicing (500k+ faces)
- User needs format conversion (OBJ → STL, GLB → STL, etc.)
- User says "fix this mesh", "repair this scan", "make it printable", "reduce polygons"

## Prerequisites

Install repair tools (one or more):

```bash
# admesh — fast CLI for STL repair (STL only)
brew install admesh           # macOS
apt-get install admesh        # Linux

# trimesh — Python library for repair + conversion (all formats)
pip install "trimesh[easy]" manifold3d fast-simplification

# pymeshlab — Python MeshLab filters (advanced: Poisson reconstruction, smoothing)
pip install pymeshlab
```

---

## Quick Repair — admesh CLI

For STL files with common scan issues. Runs all repairs by default (fix normals, fill holes, remove orphans, stitch gaps):

```bash
# Full auto-repair
admesh scan.stl --write-binary-stl=repaired.stl

# Aggressive repair for messy scans (wider tolerance, more iterations)
admesh scan.stl -n --tolerance=0.5 --iterations=5 -u -f -d -v --write-binary-stl=repaired.stl
```

| Flag | What it does |
|---|---|
| `-n` | Find and stitch nearly-adjacent facets (close gaps) |
| `-u` | Remove facets with 0 neighbors (orphans) |
| `-f` | Fill holes |
| `-d` | Fix normal directions (CW/CCW winding) |
| `-v` | Recompute normal vectors |
| `--tolerance=N` | Distance threshold for gap stitching (mm) |
| `--iterations=N` | Number of stitching passes |

**Limitation:** admesh only handles STL files. For OBJ/GLB/PLY, use trimesh.

---

## Format Conversion — trimesh

Convert between any supported formats. No repair — just format change:

```bash
claw3d mesh-convert --input model.obj --output model.stl
claw3d mesh-convert --input model.glb --output model.stl
claw3d mesh-convert --input model.ply --output model.glb
```

Or directly with Python:

```python
import trimesh
mesh = trimesh.load('model.obj', force='mesh')
mesh.export('model.stl')
```

**Supported formats:** STL, OBJ, GLB/GLTF, PLY, OFF, 3MF (with `trimesh[easy]`)

---

## Full Repair Pipeline — trimesh

For scans that need normals fixed, holes filled, and polygon count reduced:

```bash
claw3d mesh-repair --input scan.stl --output repaired.stl [--simplify 100000]
```

What this does internally:

```python
import trimesh
import trimesh.repair as repair

mesh = trimesh.load('scan.stl', force='mesh')

# Fix normals and fill holes
repair.fix_normals(mesh)
repair.fill_holes(mesh)

# Simplify if too dense (optional)
if len(mesh.faces) > 500_000:
    mesh = mesh.simplify_quadric_decimation(face_count=200_000)

mesh.export('repaired.stl')
```

### Checking Mesh Health

```python
mesh.is_watertight   # every edge shared by exactly 2 faces
mesh.is_volume       # watertight + consistent winding + outward normals
len(mesh.faces)      # polygon count
```

If `is_watertight` is False after `fill_holes`, the mesh may need pymeshlab's more aggressive repair (see below).

---

## Advanced Repair — pymeshlab

For severely broken scans, point clouds, or meshes needing Poisson reconstruction:

```bash
claw3d mesh-repair --input scan.stl --output repaired.stl --engine pymeshlab
```

### Common pymeshlab Repair Pipeline

```python
import pymeshlab

ms = pymeshlab.MeshSet()
ms.load_new_mesh('scan.stl')

# Remove degenerate geometry
ms.meshing_remove_duplicate_vertices()
ms.meshing_remove_duplicate_faces()
ms.meshing_remove_null_faces()

# Fix non-manifold topology
ms.meshing_repair_non_manifold_edges()
ms.meshing_repair_non_manifold_vertices()

# Merge close vertices (weld seams from scan artifacts)
ms.meshing_merge_close_vertices(threshold=pymeshlab.PercentageValue(0.1))

# Fill holes (maxholesize = max edges around hole perimeter)
ms.meshing_close_holes(maxholesize=50)

# Optional: smooth scan noise
ms.apply_coord_laplacian_smoothing(stepsmoothnum=2, boundary=True)

ms.save_current_mesh('repaired.stl')
```

### Poisson Surface Reconstruction (Point Cloud → Mesh)

For raw point cloud scans or meshes with too many holes to patch:

```python
ms = pymeshlab.MeshSet()
ms.load_new_mesh('pointcloud.ply')

# Compute normals from point cloud
ms.compute_normal_for_point_clouds(k=20, smoothiter=2)

# Reconstruct surface
ms.generate_surface_reconstruction_screened_poisson(depth=8, scale=1.1)

ms.save_current_mesh('reconstructed.stl')
```

### Simplification (Reduce Polygon Count)

```python
ms.meshing_decimation_quadric_edge_collapse(
    targetfacenum=50000,
    qualitythr=0.3,
    preserveboundary=True,
    preservenormal=True,
    preservetopology=True
)
```

---

## Boolean Operations — trimesh

Combine or subtract meshes (requires `manifold3d`):

```python
import trimesh

body = trimesh.load('body.stl')
cutout = trimesh.load('cutout.stl')

# Both meshes must be is_volume=True (watertight + valid winding)
result = trimesh.boolean.difference([body, cutout], engine='manifold')
result.export('body_with_hole.stl')
```

| Operation | Function |
|---|---|
| Union (merge) | `trimesh.boolean.union([a, b])` |
| Difference (cut) | `trimesh.boolean.difference([a, b])` |
| Intersection (overlap) | `trimesh.boolean.intersection([a, b])` |

---

## Workflow Decision Guide

| Problem | Tool | Command |
|---|---|---|
| STL with holes/bad normals | admesh | `admesh scan.stl --write-binary-stl=fixed.stl` |
| OBJ/GLB/PLY needs repair | trimesh | `claw3d mesh-repair --input scan.obj --output fixed.stl` |
| Too many polygons (>500k) | trimesh | `claw3d mesh-repair --input dense.stl --output simple.stl --simplify 100000` |
| Severely broken scan | pymeshlab | `claw3d mesh-repair --input broken.stl --output fixed.stl --engine pymeshlab` |
| Point cloud → solid mesh | pymeshlab | Poisson reconstruction (see above) |
| Format conversion only | trimesh | `claw3d mesh-convert --input model.obj --output model.stl` |
| Boolean ops (cut/merge) | trimesh | `trimesh.boolean.difference([a, b])` |

---

## Error Handling

| Error | Action |
|---|---|
| "not watertight" after repair | Try pymeshlab pipeline or Poisson reconstruction |
| admesh "no facets" | File is empty or corrupt; try opening in trimesh instead |
| trimesh import error | Install deps: `pip install "trimesh[easy]" manifold3d` |
| pymeshlab filter not found | Run `pymeshlab.search('keyword')` to find correct filter name |
| Boolean op fails | Both meshes must be `is_volume=True`; repair first |

<!-- /MODULE: mesh-repair -->
