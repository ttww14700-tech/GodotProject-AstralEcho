"""
Blender script: rebuild the FireRockGolem Godot-ready mesh from the original
decimated asset direction.

Use this when the previous facing-fix export turned the monster sideways in
Godot. This script intentionally applies no X/Y/Z facing correction. It copies
the original AE_FireRockGolem_Mesh_Decimated direction, bakes transform cleanup,
moves the bottom to Blender Z=0, and selects the export-ready result.
"""

import bpy
from mathutils import Vector


SOURCE_NAME_KEYWORDS = (
    "AE_FireRockGolem_Mesh_Decimated",
    "AE_FireRockGolem_mesh_Decimated",
)

WRONG_VERSION_KEYWORDS = (
    "AE_FireRockGolem_GodotReady",
    "AE_FireRockGolem_FacingFix",
)

OUTPUT_COLLECTION_NAME = "AE_FireRockGolem_GodotReady_Correct"
OUTPUT_OBJECT_NAME = "AE_FireRockGolem_GodotReady_Correct"
OUTPUT_MESH_NAME = "AE_FireRockGolem_GodotReady_Correct_Mesh"


def fail(message):
    raise RuntimeError("[AE Golem Correct Export] " + message)


def ensure_object_mode():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def is_wrong_version(obj):
    return any(keyword in obj.name for keyword in WRONG_VERSION_KEYWORDS)


def is_source_candidate(obj):
    if is_wrong_version(obj):
        return False
    return any(keyword in obj.name for keyword in SOURCE_NAME_KEYWORDS)


def collect_descendants(root):
    result = []
    pending = list(root.children)
    while pending:
        child = pending.pop(0)
        result.append(child)
        pending.extend(list(child.children))
    return result


def collect_meshes(root):
    objects = [root] + collect_descendants(root)
    return [obj for obj in objects if obj.type == "MESH"]


def candidate_score(obj):
    mesh_count = len(collect_meshes(obj))
    parent_bonus = 10 if obj.parent is None else 0
    return mesh_count + parent_bonus


def find_source_root():
    active = bpy.context.view_layer.objects.active
    if active and is_source_candidate(active):
        root = active
        while root.parent and is_source_candidate(root.parent):
            root = root.parent
        return root

    candidates = [obj for obj in bpy.data.objects if is_source_candidate(obj)]
    if not candidates:
        fail(
            "找不到原始正確方向的 AE_FireRockGolem_Mesh_Decimated。"
            "請確認原始 Decimated 版本還在場景中，不要選 FacingFix/GodotReady 錯誤版本。"
        )

    return max(candidates, key=candidate_score)


def make_clean_collection():
    old = bpy.data.collections.get(OUTPUT_COLLECTION_NAME)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)

    collection = bpy.data.collections.new(OUTPUT_COLLECTION_NAME)
    bpy.context.scene.collection.children.link(collection)
    return collection


def duplicate_meshes_to_collection(source_root, collection):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    source_meshes = collect_meshes(source_root)
    if not source_meshes:
        fail(f"{source_root.name} 底下找不到 mesh。")

    copies = []
    for source in source_meshes:
        evaluated = source.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        mesh.name = source.data.name + "_CorrectCopy"

        obj = bpy.data.objects.new(source.name + "_CorrectCopy", mesh)
        obj.matrix_world = source.matrix_world.copy()

        # Keep material slots and texture references from the source asset.
        for material_slot in source.material_slots:
            obj.data.materials.append(material_slot.material)

        collection.objects.link(obj)
        copies.append(obj)

    return copies


def join_meshes(mesh_objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in mesh_objects:
        obj.select_set(True)

    active = mesh_objects[0]
    bpy.context.view_layer.objects.active = active
    if len(mesh_objects) > 1:
        bpy.ops.object.join()
        active = bpy.context.view_layer.objects.active

    active.name = OUTPUT_OBJECT_NAME
    active.data.name = OUTPUT_MESH_NAME
    active.parent = None
    return active


def apply_rotation_scale(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def world_bbox(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    min_v = Vector((min(v.x for v in corners), min(v.y for v in corners), min(v.z for v in corners)))
    max_v = Vector((max(v.x for v in corners), max(v.y for v in corners), max(v.z for v in corners)))
    return min_v, max_v, max_v - min_v


def move_bottom_to_zero(obj):
    min_v, _max_v, _size = world_bbox(obj)
    before = min_v.z
    obj.location.z -= before
    bpy.context.view_layer.update()
    after = world_bbox(obj)[0].z
    return before, after


def set_origin_to_bottom_center(obj):
    min_v, max_v, _size = world_bbox(obj)
    bottom_center = Vector(((min_v.x + max_v.x) * 0.5, (min_v.y + max_v.y) * 0.5, 0.0))

    bpy.context.scene.cursor.location = bottom_center
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")


def count_triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def hide_wrong_versions(output_obj):
    for obj in bpy.data.objects:
        if obj == output_obj:
            continue
        if is_wrong_version(obj):
            obj.hide_set(True)
            obj.hide_viewport = True
            obj.hide_render = True


def select_output(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False


def print_result(source, obj, bottom_before, bottom_after):
    min_v, max_v, size = world_bbox(obj)
    tris = count_triangles(obj)

    print("========== AE FireRockGolem Correct Export ==========")
    print(f"[AE Golem Correct Export] Source: {source.name}")
    print(f"[AE Golem Correct Export] Output object: {obj.name}")
    print(f"[AE Golem Correct Export] Output mesh: {obj.data.name}")
    print("[AE Golem Correct Export] Facing correction: NONE")
    print("[AE Golem Correct Export] Expected Godot visual front: MonsterRoot local -Z")
    print(f"[AE Golem Correct Export] Triangles: {tris}")
    print(f"[AE Golem Correct Export] Bottom Z before: {bottom_before:.6f}")
    print(f"[AE Golem Correct Export] Bottom Z after: {bottom_after:.6f}")
    print(f"[AE Golem Correct Export] Location: {tuple(round(v, 6) for v in obj.location)}")
    print(f"[AE Golem Correct Export] Rotation Euler: {tuple(round(v, 6) for v in obj.rotation_euler)}")
    print(f"[AE Golem Correct Export] Scale: {tuple(round(v, 6) for v in obj.scale)}")
    print(f"[AE Golem Correct Export] Bounding min: {tuple(round(v, 6) for v in min_v)}")
    print(f"[AE Golem Correct Export] Bounding max: {tuple(round(v, 6) for v in max_v)}")
    print(f"[AE Golem Correct Export] Bounding size: {tuple(round(v, 6) for v in size)}")

    if size.x <= size.z:
        print(
            "[AE Golem Correct Export] WARNING: X is not wider than Z. "
            "If Godot still looks like the right-side bad screenshot, confirm the source was the original Decimated mesh."
        )
    else:
        print("[AE Golem Correct Export] SUCCESS: X > Z, matching the previously correct Godot orientation check.")

    print("========== AE FireRockGolem Correct Export End ==========")


def main():
    ensure_object_mode()

    source = find_source_root()
    collection = make_clean_collection()
    mesh_copies = duplicate_meshes_to_collection(source, collection)
    output = join_meshes(mesh_copies)

    apply_rotation_scale(output)
    bottom_before, bottom_after = move_bottom_to_zero(output)
    set_origin_to_bottom_center(output)
    apply_rotation_scale(output)

    hide_wrong_versions(output)
    select_output(output)
    print_result(source, output, bottom_before, bottom_after)


main()
