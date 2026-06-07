"""
Astral Echo Blender grey character pipeline.

Paste this file into Blender's Scripting editor, or open it as a text block and
press Run Script. This script is intentionally self-contained and uses only
Blender's built-in Python API.

Recommended current use:
1. Select the current grey character root.
2. Set RUN_MODE = "export_selected_root".
3. Run the script.
4. Export AE_TestCharacter_Grey_Final as GLB with Selected Objects enabled.

Other modes preserve the useful experiments from this greybox pass:
- "lowpoly_selected_body": duplicate the selected body mesh, reduce to <10k tris,
  make it grey, and move the bottom to world Z=0.
- "build_concept_from_body": generate a complete grey placeholder character
  around PlayerGreybox_LowPoly_Grey_Final_Mesh.
- "smooth_selected_root": duplicate the selected concept root and add temporary
  bevel/subdivision modifiers for a smoother test silhouette.
- "export_selected_root": duplicate the selected root, convert curves, apply
  modifiers, join to one mesh, grey it, put the bottom at Z=0, and select it.

Abandoned attempt, kept as project knowledge rather than executable workflow:
fitting a high-poly imported jacket to the body and deleting the hidden body
under the jacket was unreliable. It easily deleted visible body parts or left
clipping because the jacket was loose and complex. Use the procedural grey
placeholder for current Godot tests.
"""

import math

import bpy
from mathutils import Vector


# ---------------------------------------------------------------------------
# Mode
# ---------------------------------------------------------------------------

RUN_MODE = "export_selected_root"


# ---------------------------------------------------------------------------
# Shared config
# ---------------------------------------------------------------------------

FINAL_GREY_COLOR = (0.55, 0.55, 0.55, 1.0)
TRIANGLE_WARNING_LIMIT = 50000


def fail(message):
    raise RuntimeError("[AE Blender Pipeline] " + message)


def ensure_object_mode():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def make_mat(name, color):
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name)

    mat.diffuse_color = color
    mat.use_nodes = True

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.72
        bsdf.inputs["Metallic"].default_value = 0.0

    return mat


def assign_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def count_tris(obj):
    if obj.type != "MESH":
        return 0
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def count_tris_with_eval(obj):
    if obj.type != "MESH":
        return 0

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    total = sum(max(1, len(poly.vertices) - 2) for poly in mesh.polygons)
    evaluated.to_mesh_clear()
    return total


def world_bbox(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    min_v = Vector(
        (
            min(p.x for p in points),
            min(p.y for p in points),
            min(p.z for p in points),
        )
    )
    max_v = Vector(
        (
            max(p.x for p in points),
            max(p.y for p in points),
            max(p.z for p in points),
        )
    )
    return min_v, max_v, (min_v + max_v) * 0.5, max_v - min_v


def select_object(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def get_selected_root():
    active = bpy.context.view_layer.objects.active
    if active is None:
        selected = list(bpy.context.selected_objects)
        if not selected:
            fail("Select a character root or child object first.")
        active = selected[0]

    root = active
    while root.parent is not None:
        root = root.parent
    return root


def hide_hierarchy(root):
    for obj in [root] + list(root.children_recursive):
        obj.hide_set(True)
        obj.hide_viewport = True
        obj.hide_render = True


def make_clean_collection(name):
    old = bpy.data.collections.get(name)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)

    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def link_to_collection(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def duplicate_hierarchy(source_root, collection):
    source_objects = [source_root] + list(source_root.children_recursive)
    copy_map = {}

    for src in source_objects:
        copied = src.copy()
        if src.data:
            copied.data = src.data.copy()
        copied.animation_data_clear()
        copied.hide_set(False)
        copied.hide_viewport = False
        copied.hide_render = False
        copy_map[src] = copied
        collection.objects.link(copied)

    for src, copied in copy_map.items():
        copied.parent = copy_map.get(src.parent)
        copied.matrix_world = src.matrix_world.copy()

    return copy_map[source_root], list(copy_map.values())


def set_origin_to_bottom_center(obj):
    bpy.context.view_layer.update()
    min_v, max_v, _center, _size = world_bbox(obj)
    bottom_center = Vector(((min_v.x + max_v.x) * 0.5, (min_v.y + max_v.y) * 0.5, min_v.z))

    cursor_original = bpy.context.scene.cursor.location.copy()
    bpy.context.scene.cursor.location = bottom_center
    select_object(obj)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    bpy.context.scene.cursor.location = cursor_original


def move_bottom_to_zero(obj):
    bpy.context.view_layer.update()
    min_v, _max_v, _center, _size = world_bbox(obj)
    before = min_v.z
    obj.location.z -= before
    bpy.context.view_layer.update()
    after = world_bbox(obj)[0].z
    return before, after


# ---------------------------------------------------------------------------
# Step 1: low-poly grey body from selected body mesh
# ---------------------------------------------------------------------------

def lowpoly_selected_body():
    ensure_object_mode()
    source = bpy.context.view_layer.objects.active
    if source is None or source.type != "MESH":
        fail("Select the imported body mesh before running lowpoly_selected_body.")

    output_collection = make_clean_collection("AE_LowPolyBody_Output")
    body = source.copy()
    body.data = source.data.copy()
    body.animation_data_clear()
    body.name = "PlayerGreybox_LowPoly_Grey_Final_Mesh"
    body.data.name = body.name + "_Data"
    output_collection.objects.link(body)

    source.hide_set(True)
    source.hide_viewport = True
    source.hide_render = True

    before = count_tris_with_eval(body)
    if before > 10000:
        ratio = 9900 / before
        select_object(body)
        modifier = body.modifiers.new("AE_Final_Decimate", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = max(0.01, min(0.95, ratio))
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)

    mat = make_mat("AE_Greybody_Material", FINAL_GREY_COLOR)
    assign_material(body, mat)

    before_z, after_z = move_bottom_to_zero(body)
    set_origin_to_bottom_center(body)
    select_object(body)

    print("[AE Pipeline] Low-poly body output:", body.name)
    print("[AE Pipeline] Triangles:", count_tris(body))
    print("[AE Pipeline] Bottom Z before/after:", f"{before_z:.6f}", f"{after_z:.6f}")


# ---------------------------------------------------------------------------
# Step 2: procedural full-body grey concept around final low-poly body
# ---------------------------------------------------------------------------

def add_sphere(name, loc, scale, mat, collection, segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    assign_material(obj, mat)
    link_to_collection(obj, collection)
    return obj


def add_cube(name, loc, scale, mat, collection, bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    assign_material(obj, mat)
    link_to_collection(obj, collection)
    if bevel > 0:
        mod = obj.modifiers.new("AE_Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        obj.modifiers.new("AE_WeightedNormals", "WEIGHTED_NORMAL")
    return obj


def add_cone_between(name, start, end, r1, r2, mat, collection, vertices=12):
    start = Vector(start)
    end = Vector(end)
    mid = (start + end) * 0.5
    direction = end - start
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=r1,
        radius2=r2,
        depth=direction.length,
        location=mid,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    assign_material(obj, mat)
    link_to_collection(obj, collection)
    obj.modifiers.new("AE_WeightedNormals", "WEIGHTED_NORMAL")
    return obj


def add_curve(name, points, bevel_depth, mat, collection):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 8
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = 2

    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (co[0], co[1], co[2], 1.0)

    obj = bpy.data.objects.new(name, curve)
    obj.data.materials.append(mat)
    collection.objects.link(obj)
    return obj


def build_concept_from_body():
    ensure_object_mode()

    source_body = bpy.data.objects.get("PlayerGreybox_LowPoly_Grey_Final_Mesh")
    if not source_body or source_body.type != "MESH":
        fail("PlayerGreybox_LowPoly_Grey_Final_Mesh is required.")

    collection = make_clean_collection("AE_RefinedConceptGrey_Prototype")
    root = bpy.data.objects.new("AE_RefinedConceptGrey_FullBody_Test", None)
    collection.objects.link(root)

    body = source_body.copy()
    body.data = source_body.data.copy()
    body.name = "AE_Refined_BodyBase_FromLowPoly"
    body.data.name = body.name + "_Mesh"
    collection.objects.link(body)
    source_body.hide_set(True)
    source_body.hide_viewport = True
    source_body.hide_render = True

    mat_body = make_mat("AE_Refined_Body_Grey", (0.54, 0.54, 0.54, 1.0))
    mat_hair = make_mat("AE_Refined_Hair_Grey", (0.46, 0.48, 0.50, 1.0))
    mat_jacket = make_mat("AE_Refined_Jacket_LightGrey", (0.70, 0.72, 0.74, 1.0))
    mat_dark = make_mat("AE_Refined_DarkGrey", (0.20, 0.20, 0.20, 1.0))
    mat_pants = make_mat("AE_Refined_Pants_Grey", (0.30, 0.30, 0.29, 1.0))
    mat_boot = make_mat("AE_Refined_Boot_Grey", (0.16, 0.16, 0.16, 1.0))
    mat_line = make_mat("AE_Refined_Line_Grey", (0.08, 0.08, 0.08, 1.0))
    assign_material(body, mat_body)

    body_min, body_max, body_center, body_size = world_bbox(body)
    h = body_size.z
    cx, cy, z0 = body_center.x, body_center.y, body_min.z
    front_y = cy - body_size.y * 0.58
    back_y = cy + body_size.y * 0.42

    head_z = z0 + h * 0.90
    neck_z = z0 + h * 0.78
    chest_z = z0 + h * 0.68
    waist_z = z0 + h * 0.55
    hip_z = z0 + h * 0.46
    knee_z = z0 + h * 0.27
    boot_z = z0 + h * 0.06
    shoulder_w = body_size.x * 0.95
    torso_w = body_size.x * 0.82
    jacket_w = body_size.x * 1.18

    add_sphere("AE_Refined_Jacket_ChestVolume", (cx, cy, chest_z), (jacket_w * 0.50, body_size.y * 0.55, h * 0.145), mat_jacket, collection)
    add_cube("AE_Refined_Jacket_FrontFlatPanel", (cx, front_y, waist_z), (torso_w * 0.42, body_size.y * 0.045, h * 0.145), mat_jacket, collection)
    add_cone_between("AE_Refined_Jacket_FlaredSkirt", (cx, cy, waist_z), (cx, cy, hip_z - h * 0.08), jacket_w * 0.45, jacket_w * 0.58, mat_jacket, collection)
    add_cube("AE_Refined_Jacket_Back_LongHem", (cx, back_y, hip_z - h * 0.025), (jacket_w * 0.42, body_size.y * 0.055, h * 0.175), mat_jacket, collection)
    add_sphere("AE_Refined_Hood_Back", (cx, back_y, neck_z + h * 0.03), (jacket_w * 0.36, body_size.y * 0.32, h * 0.105), mat_jacket, collection)
    add_cube("AE_Refined_Dark_InnerNeck", (cx, front_y - 0.010, neck_z - h * 0.035), (torso_w * 0.24, body_size.y * 0.035, h * 0.070), mat_dark, collection)

    left_shoulder = (cx - shoulder_w * 0.48, cy, chest_z + h * 0.05)
    right_shoulder = (cx + shoulder_w * 0.48, cy, chest_z + h * 0.05)
    left_elbow = (cx - shoulder_w * 0.78, cy, waist_z + h * 0.04)
    right_elbow = (cx + shoulder_w * 0.78, cy, waist_z + h * 0.04)
    left_wrist = (cx - shoulder_w * 0.98, cy - body_size.y * 0.03, hip_z + h * 0.08)
    right_wrist = (cx + shoulder_w * 0.98, cy - body_size.y * 0.03, hip_z + h * 0.08)
    add_cone_between("AE_Refined_Left_UpperSleeve", left_shoulder, left_elbow, h * 0.065, h * 0.075, mat_jacket, collection)
    add_cone_between("AE_Refined_Right_UpperSleeve", right_shoulder, right_elbow, h * 0.065, h * 0.075, mat_jacket, collection)
    add_cone_between("AE_Refined_Left_LowerSleeve", left_elbow, left_wrist, h * 0.085, h * 0.055, mat_jacket, collection)
    add_cone_between("AE_Refined_Right_LowerSleeve", right_elbow, right_wrist, h * 0.085, h * 0.055, mat_jacket, collection)
    add_cone_between("AE_Refined_Left_DarkCuff", left_wrist, (left_wrist[0] - 0.035, left_wrist[1], left_wrist[2] - h * 0.035), h * 0.050, h * 0.040, mat_dark, collection)
    add_cone_between("AE_Refined_Right_DarkCuff", right_wrist, (right_wrist[0] + 0.035, right_wrist[1], right_wrist[2] - h * 0.035), h * 0.050, h * 0.040, mat_dark, collection)

    add_cone_between("AE_Refined_Left_CroppedPants", (cx - body_size.x * 0.18, cy, hip_z), (cx - body_size.x * 0.18, cy, knee_z), h * 0.055, h * 0.050, mat_pants, collection)
    add_cone_between("AE_Refined_Right_CroppedPants", (cx + body_size.x * 0.18, cy, hip_z), (cx + body_size.x * 0.18, cy, knee_z), h * 0.055, h * 0.050, mat_pants, collection)
    add_cube("AE_Refined_Left_Boot", (cx - body_size.x * 0.18, cy, boot_z), (body_size.x * 0.085, body_size.y * 0.28, h * 0.055), mat_boot, collection)
    add_cube("AE_Refined_Right_Boot", (cx + body_size.x * 0.18, cy, boot_z), (body_size.x * 0.085, body_size.y * 0.28, h * 0.055), mat_boot, collection)

    add_sphere("AE_Refined_Hair_Cap", (cx, cy, head_z + h * 0.035), (body_size.x * 0.31, body_size.y * 0.46, h * 0.095), mat_hair, collection)
    add_sphere("AE_Refined_Hair_BackBob", (cx, back_y, head_z - h * 0.035), (body_size.x * 0.38, body_size.y * 0.30, h * 0.125), mat_hair, collection)
    add_sphere("AE_Refined_Bangs_Left", (cx - body_size.x * 0.09, front_y - 0.010, head_z + h * 0.015), (body_size.x * 0.10, body_size.y * 0.055, h * 0.080), mat_hair, collection)
    add_sphere("AE_Refined_Bangs_Right", (cx + body_size.x * 0.07, front_y - 0.010, head_z + h * 0.020), (body_size.x * 0.11, body_size.y * 0.055, h * 0.085), mat_hair, collection)
    add_curve("AE_Refined_Ahoge_Curl", [(cx, cy, body_max.z + h * 0.015), (cx + body_size.x * 0.04, cy - body_size.y * 0.02, body_max.z + h * 0.080), (cx - body_size.x * 0.03, cy - body_size.y * 0.03, body_max.z + h * 0.115), (cx - body_size.x * 0.08, cy - body_size.y * 0.01, body_max.z + h * 0.085)], 0.008, mat_hair, collection)
    add_cube("AE_Refined_Front_Zipper_Line", (cx, front_y - 0.020, chest_z - h * 0.04), (0.006, 0.004, h * 0.170), mat_line, collection, 0)

    for obj in collection.objects:
        if obj != root:
            obj.parent = root
    select_object(root)
    print("[AE Pipeline] Concept placeholder generated:", root.name)


# ---------------------------------------------------------------------------
# Step 3: smoother visual test
# ---------------------------------------------------------------------------

def smooth_selected_root():
    ensure_object_mode()
    source_root = get_selected_root()
    collection = make_clean_collection("AE_RefinedConceptGrey_Smoother_v2")
    new_root, new_objects = duplicate_hierarchy(source_root, collection)
    new_root.name = "AE_RefinedConceptGrey_Smoother_v2"
    hide_hierarchy(source_root)

    skip_keywords = ("BodyBase", "FromLowPoly")
    for obj in new_objects:
        if obj.type != "MESH":
            continue
        for poly in obj.data.polygons:
            poly.use_smooth = True
        if not any(key in obj.name for key in skip_keywords):
            bevel = obj.modifiers.new("AE_Test_Bevel", "BEVEL")
            bevel.width = 0.006
            bevel.segments = 1
            subdiv = obj.modifiers.new("AE_Test_Subdivision", "SUBSURF")
            subdiv.levels = 1
            subdiv.render_levels = 1
        if not any(mod.type == "WEIGHTED_NORMAL" for mod in obj.modifiers):
            obj.modifiers.new("AE_Test_WeightedNormals", "WEIGHTED_NORMAL")

    select_object(new_root)
    print("[AE Pipeline] Smoother concept root:", new_root.name)


# ---------------------------------------------------------------------------
# Step 4: export-ready cleanup
# ---------------------------------------------------------------------------

def convert_curves_to_mesh(objects, collection):
    converted = []
    for obj in list(objects):
        if obj.type != "CURVE":
            continue
        select_object(obj)
        bpy.ops.object.convert(target="MESH")
        converted_obj = bpy.context.view_layer.objects.active
        converted_obj.name = obj.name + "_Mesh"
        converted.append(converted_obj)
    return list(collection.objects), converted


def apply_modifiers_and_final_material(objects, material):
    mesh_objects = []
    for obj in list(objects):
        if obj.type != "MESH":
            continue
        select_object(obj)
        for modifier in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            except Exception as exc:
                print(f"[AE Pipeline] WARNING: modifier apply failed on {obj.name}/{modifier.name}: {exc}")
        assign_material(obj, material)
        for poly in obj.data.polygons:
            poly.use_smooth = True
        mesh_objects.append(obj)
    return mesh_objects


def join_meshes(mesh_objects):
    if not mesh_objects:
        fail("No mesh objects to join.")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_objects[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = "AE_TestCharacter_Grey_Final"
    joined.data.name = "AE_TestCharacter_Grey_Final_Mesh"
    return joined


def export_selected_root():
    ensure_object_mode()
    source_root = get_selected_root()
    collection = make_clean_collection("AE_TestCharacter_ExportReady")
    _copied_root, copied_objects = duplicate_hierarchy(source_root, collection)
    hide_hierarchy(source_root)

    final_mat = make_mat("AE_TestCharacter_Final_Grey", FINAL_GREY_COLOR)
    copied_objects, converted_curves = convert_curves_to_mesh(copied_objects, collection)
    mesh_objects = apply_modifiers_and_final_material(copied_objects, final_mat)
    final_obj = join_meshes(mesh_objects)

    select_object(final_obj)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    set_origin_to_bottom_center(final_obj)
    before_z, after_z = move_bottom_to_zero(final_obj)
    set_origin_to_bottom_center(final_obj)
    select_object(final_obj)

    tris = count_tris(final_obj)
    _min_v, _max_v, center, size = world_bbox(final_obj)
    print("[AE Pipeline] Export object:", final_obj.name)
    print("[AE Pipeline] Converted curves:", len(converted_curves))
    print("[AE Pipeline] Final triangles:", tris)
    print("[AE Pipeline] Bottom Z before/after:", f"{before_z:.6f}", f"{after_z:.6f}")
    print("[AE Pipeline] Bounding size:", tuple(round(v, 6) for v in size))
    print("[AE Pipeline] Bounding center:", tuple(round(v, 6) for v in center))
    if tris > TRIANGLE_WARNING_LIMIT:
        print(f"[AE Pipeline] WARNING: {tris} tris exceeds {TRIANGLE_WARNING_LIMIT}.")
    else:
        print("[AE Pipeline] SUCCESS: selected object is ready for GLB export.")


def main():
    if RUN_MODE == "lowpoly_selected_body":
        lowpoly_selected_body()
    elif RUN_MODE == "build_concept_from_body":
        build_concept_from_body()
    elif RUN_MODE == "smooth_selected_root":
        smooth_selected_root()
    elif RUN_MODE == "export_selected_root":
        export_selected_root()
    else:
        fail(f"Unknown RUN_MODE: {RUN_MODE}")


main()
