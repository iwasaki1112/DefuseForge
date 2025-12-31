# Refactor Notes (Mobile Performance, UX-preserving)

This document summarizes UX-preserving performance improvement directions for mobile (Android/iOS).
Focus is to keep gameplay feel unchanged while reducing CPU/GPU cost.

## High Impact, Low UX Risk

### 1) Coalesce Fog Mesh Updates (Per-frame batching)
- Current: Fog mesh rebuilt on every fog update signal.
- Issue: Multiple fog updates in the same frame can trigger redundant mesh rebuilds.
- Direction: Mark "dirty" on fog update, rebuild once per frame (e.g., in _process or via call_deferred).
- UX impact: None (visuals identical, just fewer rebuilds).

### 2) Cache Enemy List (Avoid get_nodes_in_group per update)
- Current: Every fog update calls get_nodes_in_group("enemies").
- Issue: Tree scan per update adds CPU overhead.
- Direction: Maintain a cached enemy list; update on spawn/despawn (group add/remove or tree_entered/tree_exiting).
- UX impact: None (visibility logic unchanged).

### 3) Cache Ray Directions for Vision
- Current: Each vision update recomputes ray directions via rotation per ray.
- Issue: Per-frame trig/rotation cost multiplies by ray_count and units.
- Direction: Precompute angle offsets (or direction vectors in local space) once, then transform by character basis each update.
- UX impact: None (same rays, same resolution).

### 4) Reduce Fog Mesh Work per Component
- Current: SurfaceTool adds vertices and generates normals every update.
- Issue: Normals are unnecessary for unshaded material; generate_normals is extra cost.
- Direction: Skip generate_normals for unshaded mesh; use fixed normal or none.
- UX impact: None (unshaded, same appearance).

## Medium Impact, Low UX Risk

### 5) Defer Enemy Visibility Checks When Not Needed
- Current: Every fog update computes visibility even if no enemy nearby or no component changed.
- Direction: Track "dirty" components or a bounding region; only recalc enemy visibility if any component changed this frame.
- UX impact: None if same update cadence is preserved.

### 6) Fog Mesh Culling (Avoid extra_cull_margin=1000)
- Current: extra_cull_margin=1000 disables culling effectively.
- Issue: GPU draws fog/path even when offscreen.
- Direction: Use a reasonable cull margin based on view_distance; or update bounds as needed.
- UX impact: None (only offscreen culling).

### 7) Path Renderer Update Scope
- Current: Path renderer rebuilds surfaces for entire path on every draw update.
- Direction: Only rebuild when path changes; avoid redraw on stable frames.
- UX impact: None (same path visuals).

## Lower Impact, Safe Cleanup

### 8) Avoid Per-frame Material Updates for Selection Ring
- Current: Selection indicator material color updated every frame.
- Direction: Update only when selected player changes or color changes.
- UX impact: None.

### 9) Minimize Allocations in Vision/Fog
- Current: Visible points arrays cleared and appended each update.
- Direction: Reuse arrays or pre-allocate buffers; avoid temporary arrays where possible.
- UX impact: None.

## Optional (Device-tiered, Still UX-safe if calibrated)

### 10) Dynamic LOD for Ray Count (Quality-preserving)
- Idea: Keep user-visible smoothness by adapting ray_count to device performance while preserving FOV and distance.
- Direction: On low-end devices, lower ray_count but keep interpolation for smooth edge; ideally no noticeable quality loss.
- UX impact: Low if interpolation is used.

## Notes

- Focus areas are vision, fog rendering, and path rendering because they run frequently and scale with unit count.
- Suggested changes are targeted to reduce CPU time and GPU overdraw without reducing update cadence or visual fidelity.
