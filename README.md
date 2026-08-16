# RM ImportClean

**RM ImportClean** is a professional geometry optimization and cleanup tool for **Autodesk 3ds Max**. Built to handle heavy architectural and industrial CAD/BIM models (Revit, Rhino, SketchUp, ArchiCAD, STEP/IGES, FBX, OBJ), it simplifies complex meshes, removes redundant topology, and isolates repeated elements in seconds.

---

## ✨ Key Modules & Features

### 1. 🔄 Smart Revit / CAD Mesh-to-Poly Converter
Standard 3ds Max *Convert to Poly* often destroys rounded corners and creates non-planar polygon artifacts on CAD meshes.
* **Non-Convex Polygon Protection**: Preserves roundings and prevents polygon collapse.
* **Planar Threshold Validation**: Ensures only truly coplanar triangles are merged into n-gons.
* **Mid-Edge Vertex Retention**: Keeps critical boundary vertices to avoid silhouette distortion.
* **Configurable Max N-gon Size**: Control max edges per polygon (Tri/Quad/N-gon).

### 2. 🧹 Redundant Topology & Vertex Cleaner
Cleans up millions of redundant vertices and coplanar edges without damaging model details.
* **Coplanar Edge Optimizer**: Removes invisible triangulation and diagonal dividing edges while strictly respecting:
  * **Material IDs** (preserves multi-sub materials)
  * **Smoothing Groups** (prevents shading errors)
  * **UV Seams & Mapping Channels** (texture coordinates remain 100% intact)
* **Collinear Vertex Welder**: Detects and cleans straight-line edge vertices within user-defined angular tolerances.

### 3. 🔍 Identical Element Analyzer & Filter
Categorizes connected geometry elements using deep geometric signature matching (vertex/polygon counts, sorted centroid distance profiles, and bounding box dimensions).
* **Duplicate Detection**: Identifies repeated components (windows, bolts, mullions, panels, imported dust/artifacts).
* **Multi-Criteria Sorting**: Sort by element size (smallest first) or frequency (most repeated first).
* **Fast Bounding Size Filter**: Instantly select all geometry elements smaller than a specified size threshold.
* **Delete & Detach**:
  * **Delete**: Instantly purge selected artifacts and optimize scene weight.
  * **Detach**: Separate highlighted element groups into independent scene objects with automated naming, transform preservation, and isolated vertex cleanup.
  * Full **Undo (`Ctrl+Z`)** support.

---

## 🎨 User Interface
* **Sleek Frameless Design**: Custom DotNet title bar styled in harmony with the **RM Tools** ecosystem.
* **Smooth Window Dragging**: Responsive drag-and-drop window positioning.
* **Collapsible Sub-Rollouts**: Compact, organized workflow panels with smooth scrolling.

---

## 🚀 Installation

1. **Drag and Drop**: Simply drag and drop the `RM_ImportClean.mzp` file into any active **3ds Max** viewport.
2. **Add Button to Toolbar**:
   - In 3ds Max, go to: `Customize` ➔ `Customize User Interface` (or `Hotkey & Toolbar Editor`).
   - Switch to the **Toolbars** tab.
   - In the **Category** drop-down list, select: `RM scripts`.
   - Drag **Import Clean** onto any toolbar or custom quad menu.

---

## 🛠️ Compatibility
* **Autodesk 3ds Max**: 2020, 2021, 2022, 2023, 2024, 2025, 2026+
* **Object Types**: `Editable Poly`, `Editable Mesh`
* **OS**: Windows 10 / 11 (64-bit)

---

## 👤 Author & Support
* **Telegram Channel**: [@refer_manage](https://t.me/refer_manage)
* **GitHub Repository**: [RM_ImportClean](https://github.com/rmatveichuk/RM_ImportClean)
