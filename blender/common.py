"""Scene-independent helpers shared by the pre-rendered themes' Blender
scripts (poppy/poppy.py, orchid/orchid.py): Cycles and compositor setup with
light-group relighting, lights, materials, and building meshes and hair.

The scripts import it with blender/ on sys.path:
  sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "blender"))
"""

import math

import bpy
from mathutils import Vector


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def smoothstep(e0, e1, x):
    x = clamp01((x - e0) / (e1 - e0))
    return x * x * (3 - 2 * x)


def lerp(a, b, x):
    return a + (b - a) * x


def setup_render(scene, res, samples, look="AgX - High Contrast", exposure=-0.9):
    scene.render.engine = "CYCLES"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.cycles.samples = samples
    # Denoising happens per light group in the compositor (setup_compositor).
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 12
    scene.cycles.transmission_bounces = 12
    scene.cycles.transparent_max_bounces = 24
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = look
        scene.view_settings.exposure = exposure
    except TypeError:
        pass

    # Prefer OptiX, then CUDA; fall back to CPU if neither is available.
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
        except TypeError:
            continue
        prefs.refresh_devices()
        gpus = [d for d in prefs.devices if d.type == kind]
        if gpus:
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = "GPU"
            print("Cycles device:", kind, [d.name for d in gpus])
            return
    print("Cycles device: CPU")


def setup_compositor(scene, out_dir, levels):
    """Light transport is linear, so one render can be relit afterwards. The
    backlights are one light group and everything else another; each is
    denoised on its own, then the output for each level is
    key * strength + ambient, saved with the scene's view transform."""
    layer = bpy.context.view_layer
    for group in ("key", "ambient"):
        layer.lightgroups.add(name=group)
    layer.cycles.denoising_store_passes = True

    nt = bpy.data.node_groups.new("Relight", "CompositorNodeTree")
    scene.compositing_node_group = nt
    passes = nt.nodes.new("CompositorNodeRLayers")
    clean = {}
    for group in ("key", "ambient"):
        dn = nt.nodes.new("CompositorNodeDenoise")
        set_inputs(dn, HDR=True)
        nt.links.new(passes.outputs["Combined_" + group], dn.inputs["Image"])
        nt.links.new(passes.outputs["Denoising Albedo"], dn.inputs["Albedo"])
        nt.links.new(passes.outputs["Denoising Normal"], dn.inputs["Normal"])
        clean[group] = dn.outputs["Image"]

    save = nt.nodes.new("CompositorNodeOutputFile")
    save.directory = out_dir
    save.format.media_type = "IMAGE"
    save.format.file_format = "JPEG"
    save.format.quality = 92
    save.format.color_mode = "RGB"
    for name, strength in levels.items():
        save.file_output_items.new("RGBA", name)
        relit = nt.nodes.new("ShaderNodeVectorMath")
        relit.operation = "MULTIPLY_ADD"
        relit.inputs[1].default_value = (strength,) * 3
        nt.links.new(clean["key"], relit.inputs[0])
        nt.links.new(clean["ambient"], relit.inputs[2])
        nt.links.new(relit.outputs["Vector"], save.inputs[name])
    return save


def node_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return mat, nt, out


def set_inputs(node, **values):
    # Socket names with spaces are given with underscores, e.g. Subsurface_Weight.
    for key, value in values.items():
        name = key.replace("_", " ")
        if name in node.inputs:
            node.inputs[name].default_value = value


def add_area_light(name, location, target, energy, size, color, group):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    obj.lightgroup = group
    bpy.context.collection.objects.link(obj)
    obj.location = location
    direction = (Vector(target) - Vector(location)).normalized()
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(direction)
    return obj


def replace_mesh(obj, verts, faces, uvs=None, attrs=None):
    mesh = bpy.data.meshes.new(obj.name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    if uvs:
        layer = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                layer.data[li].uv = uvs[mesh.loops[li].vertex_index]
    for name, values in (attrs or {}).items():
        mesh.attributes.new(name, "FLOAT", "POINT").data.foreach_set("value", values)
    mesh.shade_smooth()
    old = obj.data
    mats = list(old.materials)
    obj.data = mesh
    for m in mats:
        mesh.materials.append(m)
    bpy.data.meshes.remove(old)


def new_object(name, parent=None, material=None):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if material:
        mesh.materials.append(material)
    if parent:
        obj.parent = parent
    return obj


def new_hair(name, material, parent=None):
    curves = bpy.data.hair_curves.new(name)
    curves.materials.append(material)
    obj = bpy.data.objects.new(name, curves)
    bpy.context.collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def replace_hair(obj, strands):
    """Rebuilds a hair object from strands, each a list of (point, radius)."""
    curves = bpy.data.hair_curves.new(obj.name)
    curves.add_curves([len(s) for s in strands])
    curves.attributes["position"].data.foreach_set("vector", [c for s in strands for p, _ in s for c in p])
    radius = curves.attributes.get("radius") or curves.attributes.new("radius", "FLOAT", "POINT")
    radius.data.foreach_set("value", [r for s in strands for _, r in s])
    old = obj.data
    for m in old.materials:
        curves.materials.append(m)
    obj.data = curves
    bpy.data.hair_curves.remove(old)


def basis(axis):
    """Two unit vectors perpendicular to axis. Built against the camera's
    depth axis, so they turn smoothly as the stem bends from frame to frame
    (Vector.orthogonal can flip) and hairs stay put."""
    a = axis.cross(Vector((0, 1, 0)))
    if a.length < 1e-6:
        a = axis.cross(Vector((1, 0, 0)))
    a.normalize()
    return a, axis.cross(a).normalized()


def add_ellipsoid(verts, faces, centre, axis, half_len, radius, rings=6, segs=8):
    a, b = basis(axis)
    start = len(verts)
    verts.append(centre + axis * half_len)
    for i in range(1, rings):
        ang = math.pi * i / rings
        for j in range(segs):
            be = 2 * math.pi * j / segs
            verts.append(centre + axis * (math.cos(ang) * half_len)
                         + (a * math.cos(be) + b * math.sin(be)) * (math.sin(ang) * radius))
    bottom = len(verts)
    verts.append(centre - axis * half_len)
    for j in range(segs):
        faces.append((start, start + 1 + j, start + 1 + (j + 1) % segs))
    for i in range(rings - 2):
        r0 = start + 1 + i * segs
        r1 = r0 + segs
        for j in range(segs):
            faces.append((r0 + j, r1 + j, r1 + (j + 1) % segs, r0 + (j + 1) % segs))
    last = start + 1 + (rings - 2) * segs
    for j in range(segs):
        faces.append((last + (j + 1) % segs, last + j, bottom))


def lathe(profile, segs, ripple=lambda phi, k: 1.0):
    """Surface of revolution about Z from (r, z) pairs, bottom to top, closed
    with a point at the top. ripple(phi, k) scales the radius of ring k."""
    verts, faces = [], []
    for k, (r, z) in enumerate(profile):
        for j in range(segs):
            phi = 2 * math.pi * j / segs
            rr = r * ripple(phi, k)
            verts.append(Vector((rr * math.cos(phi), rr * math.sin(phi), z)))
    for k in range(len(profile) - 1):
        for j in range(segs):
            a, b = k * segs + j, k * segs + (j + 1) % segs
            faces.append((a, b, b + segs, a + segs))
    top = len(verts)
    verts.append(Vector((0, 0, profile[-1][1])))
    last = (len(profile) - 1) * segs
    for j in range(segs):
        faces.append((last + j, last + (j + 1) % segs, top))
    return verts, faces
