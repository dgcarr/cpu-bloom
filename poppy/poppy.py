"""Procedural poppy for the CPU Bloom "poppy" theme, rendered with Cycles.

One bloom parameter t in [0, 1] drives the whole pose:
  0    closed bud of furled, crumpled red petals
  0.5  three-quarter view, half open (the reference look)
  1    fully open and turned to face the camera
Each output frame is one evenly spaced value of t, so the Processing theme can
scrub the sequence forwards and backwards. Every frame is saved twice, with a
dim and a bright backlight (out/dim/, out/bright/), and the theme blends the
two by CPU temperature.

Usually run through poppy/render.sh. Directly:
  blender -b --factory-startup -P poppy/poppy.py -- --preview 0,0.5,1 --res 640 --out /tmp/poppy
  blender -b --factory-startup -P poppy/poppy.py -- --frames 121 --res 1280 --out cpu_bloom/data/poppy
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Quaternion, Vector, noise

Z = Vector((0, 0, 1))


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--preview", help="comma-separated t values to render instead of a sequence")
    p.add_argument("--frames", type=int, default=121, help="number of evenly spaced t values")
    p.add_argument("--start", type=int, default=0, help="first frame to render, to resume a stopped run")
    p.add_argument("--res", type=int, default=1280)
    p.add_argument("--samples", type=int, default=192)
    p.add_argument("--dim", type=float, default=0.5, help="backlight strength for a cool CPU")
    p.add_argument("--bright", type=float, default=1.6, help="backlight strength for a hot CPU")
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def smoothstep(e0, e1, x):
    x = clamp01((x - e0) / (e1 - e0))
    return x * x * (3 - 2 * x)


def lerp(a, b, x):
    return a + (b - a) * x


def ease(x):
    """Front-loads the opening a little so t=0.5 reads as half open."""
    return clamp01(x) ** 0.8


# ---------------------------------------------------------------- scene setup

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def setup_render(scene, res, samples):
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
        scene.view_settings.look = "AgX - High Contrast"
        scene.view_settings.exposure = -0.9
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


EDGE_FADE = 0.05  # width of the petals' soft edge, in scene units (petals are ~0.8 long)


def petal_material():
    mat, nt, out = node_material("Petal")
    uv = nt.nodes.new("ShaderNodeUVMap")

    # Colour: deep crimson at the base to hot pink at the edge (UV x = along the petal).
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0.26, 0.0, 0.09, 1)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (0.90, 0.10, 0.40, 1)
    mid = cr.elements.new(0.35)
    mid.color = (0.62, 0.006, 0.22, 1)
    nt.links.new(sep.outputs["X"], ramp.inputs["Fac"])

    # Veins: noise stretched along the petal, so the streaks are irregular in
    # spacing and length rather than an even weave. The big crepe pleats are
    # in the geometry; this only adds faint fine detail.
    stretch = nt.nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (2.5, 60.0, 1.0)
    nt.links.new(uv.outputs["UV"], stretch.inputs["Vector"])
    veins = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(veins, Scale=1.0, Detail=3.0, Roughness=0.5, Distortion=0.3)
    nt.links.new(stretch.outputs["Vector"], veins.inputs["Vector"])
    crinkle = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(crinkle, Scale=22.0, Detail=4.0, Roughness=0.6)
    nt.links.new(uv.outputs["UV"], crinkle.inputs["Vector"])
    mix_h = nt.nodes.new("ShaderNodeMath")
    mix_h.operation = "MULTIPLY_ADD"
    mix_h.inputs[1].default_value = 0.6
    nt.links.new(crinkle.outputs["Fac"], mix_h.inputs[0])
    nt.links.new(veins.outputs["Fac"], mix_h.inputs[2])
    bump = nt.nodes.new("ShaderNodeBump")
    set_inputs(bump, Strength=0.18, Distance=0.002)
    nt.links.new(mix_h.outputs[0], bump.inputs["Height"])

    # The veins are a touch darker than the tissue between them.
    shade = nt.nodes.new("ShaderNodeMixRGB")
    shade.blend_type = "MULTIPLY"
    vein_fac = nt.nodes.new("ShaderNodeMapRange")
    set_inputs(vein_fac, From_Min=0.45, From_Max=0.7, To_Min=0.0, To_Max=0.22)
    nt.links.new(veins.outputs["Fac"], vein_fac.inputs["Value"])
    nt.links.new(vein_fac.outputs["Result"], shade.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], shade.inputs["Color1"])
    shade.inputs["Color2"].default_value = (0.55, 0.15, 0.30, 1)
    colour = shade.outputs["Color"]

    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    set_inputs(bsdf, Roughness=0.68, Specular_IOR_Level=0.25, Subsurface_Weight=0.3, Subsurface_Scale=0.02,
               Sheen_Weight=0.15, Sheen_Roughness=0.5)
    if "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.15, 0.2)
    nt.links.new(colour, bsdf.inputs["Base Color"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    # Thin petals glow when backlit: mix in a saturated translucent layer.
    trans = nt.nodes.new("ShaderNodeBsdfTranslucent")
    gain = nt.nodes.new("ShaderNodeMixRGB")
    gain.blend_type = "MULTIPLY"
    set_inputs(gain, Fac=1.0)
    gain.inputs["Color2"].default_value = (1.0, 0.36, 0.72, 1)
    nt.links.new(colour, gain.inputs["Color1"])
    nt.links.new(gain.outputs["Color"], trans.inputs["Color"])
    nt.links.new(bump.outputs["Normal"], trans.inputs["Normal"])

    mix = nt.nodes.new("ShaderNodeMixShader")
    set_inputs(mix, Fac=0.5)
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(trans.outputs[0], mix.inputs[2])

    # Semi-transparent: overlapping petals, stamens and the background show
    # through faintly, tinted by the petal colour.
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    tint = nt.nodes.new("ShaderNodeMixRGB")
    set_inputs(tint, Fac=0.9)
    tint.inputs["Color1"].default_value = (1, 1, 1, 1)
    nt.links.new(colour, tint.inputs["Color2"])
    nt.links.new(tint.outputs["Color"], clear.inputs["Color"])
    see_through = nt.nodes.new("ShaderNodeMixShader")
    set_inputs(see_through, Fac=0.18)
    nt.links.new(mix.outputs[0], see_through.inputs[1])
    nt.links.new(clear.outputs[0], see_through.inputs[2])

    # The tissue thins towards the rim and sides, so the petal fades out over
    # the last EDGE_FADE units instead of ending in a hard cut edge.
    edge = nt.nodes.new("ShaderNodeAttribute")
    edge.attribute_name = "edge"
    opacity = nt.nodes.new("ShaderNodeMapRange")
    opacity.interpolation_type = "SMOOTHSTEP"
    set_inputs(opacity, From_Min=0.0, From_Max=EDGE_FADE)
    nt.links.new(edge.outputs["Fac"], opacity.inputs["Value"])
    gone = nt.nodes.new("ShaderNodeBsdfTransparent")
    fade = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(opacity.outputs["Result"], fade.inputs["Fac"])
    nt.links.new(gone.outputs[0], fade.inputs[1])
    nt.links.new(see_through.outputs[0], fade.inputs[2])
    nt.links.new(fade.outputs[0], out.inputs["Surface"])
    return mat


def simple_material(name, color, roughness=0.5, subsurface=0.0, sheen=0.0, specular=0.5, transmission=0.0):
    mat, nt, out = node_material(name)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    set_inputs(bsdf, Roughness=roughness, Subsurface_Weight=subsurface, Subsurface_Scale=0.01,
               Sheen_Weight=sheen, Specular_IOR_Level=specular, Transmission_Weight=transmission)
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def water_material():
    mat, nt, out = node_material("Water")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
    set_inputs(bsdf, Roughness=0.0, IOR=1.33, Transmission_Weight=1.0)
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def grain_material(name, color_a, color_b, scale, roughness=0.5, subsurface=0.3, sheen=0.0, attribute=None):
    """Mottled colour and a fine granular bump, for the seed pod and stigma.
    With `attribute`, a per-vertex mask blends towards color_b instead (the
    stigma's raised rays)."""
    mat, nt, out = node_material(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grain = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(grain, Scale=scale, Detail=6.0, Roughness=0.7)
    nt.links.new(tc.outputs["Object"], grain.inputs["Vector"])
    mottle = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(mottle, Scale=scale * 0.08, Detail=3.0)
    nt.links.new(tc.outputs["Object"], mottle.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    a_in, b_in = [s for s in mix.inputs if s.type == "RGBA"]
    a_in.default_value = (*color_a, 1)
    b_in.default_value = (*color_b, 1)
    if attribute:
        attr = nt.nodes.new("ShaderNodeAttribute")
        attr.attribute_name = attribute
        nt.links.new(attr.outputs["Fac"], mix.inputs[0])
    else:
        nt.links.new(mottle.outputs["Fac"], mix.inputs[0])
    bump = nt.nodes.new("ShaderNodeBump")
    set_inputs(bump, Strength=0.35, Distance=0.001)
    nt.links.new(grain.outputs["Fac"], bump.inputs["Height"])
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    set_inputs(bsdf, Roughness=roughness, Subsurface_Weight=subsurface, Subsurface_Scale=0.01,
               Sheen_Weight=sheen, Sheen_Roughness=0.4)
    nt.links.new([s for s in mix.outputs if s.type == "RGBA"][0], bsdf.inputs["Base Color"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def setup_world_and_backdrop(scene):
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.lightgroup = "ambient"
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.012, 0.050, 0.045, 1)
    bg.inputs["Strength"].default_value = 1.0

    # A soft teal glow behind the flower that fades to one flat colour well
    # inside the frame edge, so the theme can extend the background seamlessly.
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0.3, 7.0, 0.2), rotation=(math.radians(90), 0, 0))
    plane = bpy.context.object
    plane.name = "Backdrop"
    plane.lightgroup = "ambient"
    for attr in ("visible_diffuse", "visible_glossy", "visible_transmission", "visible_shadow",
                 "visible_volume_scatter"):
        setattr(plane, attr, False)
    mat, nt, out = node_material("Backdrop")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Location"].default_value = (0.0, 0.0, 0.0)
    nt.links.new(tc.outputs["Object"], mapping.inputs["Vector"])
    length = nt.nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    nt.links.new(mapping.outputs["Vector"], length.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = "EASE"
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0.040, 0.140, 0.125, 1)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (0.012, 0.050, 0.045, 1)
    # Plane units: fade out well inside the frame edge (the camera sees about +-3).
    scale = nt.nodes.new("ShaderNodeMath")
    scale.operation = "DIVIDE"
    scale.inputs[1].default_value = 2.4
    nt.links.new(length.outputs["Value"], scale.inputs[0])
    nt.links.new(scale.outputs[0], ramp.inputs["Fac"])
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    plane.data.materials.append(mat)


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


def setup_camera(scene):
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 70  # wide enough that no pose touches the frame edge
    cam_data.sensor_width = 36
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = 5.6
    cam_data.dof.focus_distance = 4.8
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, -4.8, -0.05)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    return cam


# ------------------------------------------------------------------- geometry

# The head sits upper right while closed (as in the reference) and drifts
# towards the centre as it turns to face the camera, so the full bloom fits.
HEAD_SIDE = Vector((0.22, 0.0, 0.20))
HEAD_FRONT = Vector((0.0, 0.0, 0.02))
HEAD_POS = HEAD_SIDE

def make_petals():
    """Two whorls of four, the inner one offset by 45 degrees, shorter and
    more upright when open so the layering shows. Each petal gets its own
    small variations so the open flower is never a perfect circle."""
    rng = random.Random(11)
    petals = []
    whorls = [  # (angle offset, length, half fan, base radius, open angle, delay)
        (0, 0.90, 58, 0.080, 64, 0.00),
        (45, 0.76, 55, 0.064, 48, 0.03),
    ]
    for w, (offset, length, half, base_r, open_deg, delay) in enumerate(whorls):
        for k in range(4):
            petals.append({
                "gamma": offset + 90 * k + rng.uniform(-9, 9),
                "length": length * rng.uniform(0.86, 1.10),
                "half": half + rng.uniform(-5, 5),
                "base_r": base_r,
                "open": open_deg + rng.uniform(-9, 9),
                "delay": delay + rng.uniform(0.0, 0.05),
                "seed": 1.0 + 4 * w + k,
                "folds": [(rng.uniform(-0.55, 0.55), rng.choice((-1, 1)) * rng.uniform(0.02, 0.045))
                          for _ in range(rng.choice((1, 2)))],
            })
    return petals


PETALS = make_petals()
NU, NV = 64, 170


def petal_geometry(spec, t):
    length, base_r, delay, seed = spec["length"], spec["base_r"], spec["delay"], spec["seed"]
    half = math.radians(spec["half"])
    tp = smoothstep(0.0, 1.0, ease((t - delay) / (1.0 - delay))) if t > delay else 0.0

    # Closed: leaning out a little then curled in at the tip, wrapped across
    # the width. Open: a deep cup whose rim flares outwards.
    theta = math.radians(lerp(30, spec["open"], tp))  # angle from the axis at the base
    bend = math.radians(lerp(-100, 30, tp))     # extra angle reached at the tip
    wrap = math.radians(lerp(125, 52, tp))     # cross-wise curl at the edges
    length *= lerp(0.90, 1.0, tp)
    crumple = lerp(0.030, 0.018, tp)
    pleat = lerp(0.014, 0.030, tp)
    ruffle = lerp(0.006, 0.030, tp)

    g = math.radians(spec["gamma"])
    e = Vector((math.cos(g), math.sin(g), 0))
    et = Vector((-e.y, e.x, 0))

    # Centreline: integrate the bending petal so it keeps its length.
    n = 200
    centre, tangent, inward = [Vector((0, 0, 0))], [], []
    for i in range(n + 1):
        s = i / n
        a = theta + bend * s * s
        tangent.append(math.cos(a) * Z + math.sin(a) * e)
        inward.append(math.sin(a) * Z - math.cos(a) * e)
    for i in range(n):
        centre.append(centre[-1] + tangent[i] * (length / n))

    def frame_at(s):
        f = clamp01(s) * n
        i = min(int(f), n - 1)
        w = f - i
        return centre[i].lerp(centre[i + 1], w), inward[i].lerp(inward[i + 1], w)

    def pleats(u, v):
        """Crepe-paper pleats: ridged noise across the width, stretched along
        the petal so each crease runs from the base towards the rim and
        wanders a little. Sharp ridges, irregular spacing, about 15 across."""
        wander = 0.5 * noise.noise(Vector((u * 1.4, v * 1.7, seed * 2.9)))
        q = Vector((v * 6.5 + wander, u * 0.6, seed * 5.3))
        r1 = 1 - abs(noise.noise(q))
        r2 = 1 - abs(noise.noise(q * 2.2 + Vector((0, 0, 3.7))))
        return r1 ** 7 + 0.35 * r2 ** 7 - 0.3

    verts, uvs, edge = [], [], []
    for iu in range(NU + 1):
        u = iu / NU
        for iv in range(NV + 1):
            v = iv / NV * 2 - 1
            phi = v * half
            # Broad fan with a shallow notch at the tip, an irregular,
            # petal-specific wobble, and small scallops where the pleats meet
            # the rim, so no two petals share a silhouette.
            outline = (1 - 0.14 * v ** 2 - 0.22 * v ** 6 - 0.05 * math.exp(-(v / 0.14) ** 2)
                       + 0.07 * noise.noise(Vector((v * 2.0, seed * 3.3, 0.5)))
                       + 0.025 * pleats(1.0, v))
            r = u * outline
            xr = r * math.cos(phi)
            xt = r * math.sin(phi) * length
            half_w = max(r * math.sin(half) * length, 1e-5)
            psi = wrap * (xt / half_w)
            rho = half_w / wrap
            xt2 = rho * math.sin(psi)
            curl = rho * (1 - math.cos(psi))

            p = Vector((u * 3.2, v * 4.0, seed * 7.1))
            crumple_d = (noise.noise(p) + 0.5 * noise.noise(p * 2.3) + 0.25 * noise.noise(p * 5.1)) \
                * crumple * u ** 0.6
            pleat_d = pleat * u ** 0.7 * pleats(u, v)
            # Big soft creases.
            fold_d = sum(a * u * math.exp(-((v - v0) / 0.13) ** 2) for v0, a in spec["folds"])
            ruffle_d = ruffle * smoothstep(0.55, 1.0, u) * (math.sin(v * math.pi * 3.2 + 2.5 * noise.noise(p * 0.9))
                                                            + 0.6 * noise.noise(Vector((v * 3.0, u * 2.0, seed))))

            c, nin = frame_at(xr)
            verts.append(e * base_r + c + et * xt2 + nin * (curl + crumple_d + pleat_d + ruffle_d + fold_d))
            uvs.append((u, (v + 1) / 2))
            # Distance to the nearest free edge, the rim or a side, for the
            # material's edge fade. The sides meet at the base, which is
            # hidden in the centre, so they don't fade all the way down.
            rim_d = (1 - u) * outline * length
            side_d = (1 - abs(v)) * half * max(u, 0.35) * outline * length
            edge.append(min(rim_d, side_d))

    faces = []
    row = NV + 1
    for iu in range(NU):
        for iv in range(NV):
            a = iu * row + iv
            faces.append((a, a + 1, a + row + 1, a + row))
    return verts, faces, uvs, edge


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


def add_droplet(verts, faces, base, normal, radius, surface_r=None, rings=7, segs=16):
    """A sessile water drop: a spherical cap with a 105 degree contact angle,
    flattened a little by its weight, sitting on `base` with its axis along
    `normal`. It sinks slightly into the surface so it never floats; on a
    curved surface of radius surface_r, by the extra gap under its rim too."""
    contact = math.radians(105)
    flat = 0.82
    lift = -radius * math.cos(contact)  # sphere centre above the contact plane
    sink = 0.2 * radius + 0.0012
    if surface_r:
        sink += (radius * math.sin(contact)) ** 2 / (2 * surface_r)
    a, b = basis(normal)
    start = len(verts)
    verts.append(base + normal * ((lift + radius) * flat - sink))
    for i in range(1, rings + 1):
        al = contact * i / rings
        for j in range(segs):
            be = 2 * math.pi * j / segs
            verts.append(base + (a * math.cos(be) + b * math.sin(be)) * (radius * math.sin(al))
                         + normal * ((lift + radius * math.cos(al)) * flat - sink))
    bottom = len(verts)
    verts.append(base - normal * sink)
    for j in range(segs):
        faces.append((start, start + 1 + j, start + 1 + (j + 1) % segs))
    for i in range(rings - 1):
        r0 = start + 1 + i * segs
        r1 = r0 + segs
        for j in range(segs):
            faces.append((r0 + j, r1 + j, r1 + (j + 1) % segs, r0 + (j + 1) % segs))
    last = start + 1 + (rings - 1) * segs
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


# ------------------------------------------------------------------- centre

RAYS = 10  # stigmatic rays on the seed pod's cap


def pod_radius(z):
    """The seed pod: an egg narrowing to a short neck under the cap."""
    zz = clamp01((z - 0.005) / 0.12)
    return 0.031 + 0.019 * math.sin(math.pi * zz ** 0.9) - 0.009 * zz ** 4


def pod_geometry():
    profile = [(pod_radius(z), z) for z in (0.005 + 0.12 * i / 30 for i in range(31))]
    # Shallow ribs, one under each ray of the cap, fading out at both ends.
    return lathe(profile, 80, lambda phi, k: 1 + 0.04 * math.cos(RAYS * phi) * math.sin(math.pi * k / 30))


def cap_geometry():
    """The stigma: a low, lobed lid overhanging the pod, with a raised ray
    running from the centre out to each lobe. Returns the mesh and a per-vertex
    'ray' mask the material uses to colour the rays."""
    segs, n_top, n_under = 12 * RAYS, 28, 8
    # Rings from the top centre out to the rim, then in underneath to the pod:
    # (radius scale, z, ray height, how lobed, ray colour).
    rings = []
    for i in range(1, n_top + 1):
        rho = i / n_top
        rings.append((rho, 0.150 - 0.016 * rho ** 2 - 0.008 * rho ** 6, rho ** 0.5 * (1 - rho) ** 0.4, 1.0, 1.0))
    for i in range(1, n_under + 1):
        k = i / n_under
        rings.append((lerp(1.0, 0.38, k), lerp(0.123, 0.118, k) - 0.004 * math.sin(math.pi * k), 0.0, 1 - k, 0.0))
    verts, faces, ray = [Vector((0, 0, 0.150))], [], [1.0]
    for rho, z, ridge, lobed, tinted in rings:
        for j in range(segs):
            phi = 2 * math.pi * j / segs
            c = 0.5 + 0.5 * math.cos(RAYS * phi)
            rim = 0.060 * lerp(1.0, 0.84 + 0.16 * c ** 0.7, lobed)  # a lobe at each ray
            mask = c ** 12
            r = rho * rim
            verts.append(Vector((r * math.cos(phi), r * math.sin(phi), z + 0.005 * mask * ridge)))
            ray.append(mask * tinted)
    for j in range(segs):
        faces.append((0, 1 + j, 1 + (j + 1) % segs))
    for k in range(len(rings) - 1):
        for j in range(segs):
            a, b = 1 + k * segs + j, 1 + k * segs + (j + 1) % segs
            faces.append((a, a + segs, b + segs, b))
    return verts, faces, ray


def receptacle_profile(z):
    """Where stem meets flower: the stem swells smoothly into the base of the
    petals rather than ending in a knob."""
    return 0.0422 + 0.026 * smoothstep(-0.09, 0.015, z) ** 1.7


def receptacle_geometry():
    profile = [(receptacle_profile(z), z) for z in (-0.12 + 0.135 * i / 24 for i in range(25))]
    profile += [(0.050, 0.020), (0.034, 0.022)]
    return lathe(profile, 48)


def receptacle_hairs(rng_seed=4, count=160):
    rng = random.Random(rng_seed)
    strands = []
    for _ in range(count):
        z = rng.uniform(-0.11, -0.025)
        phi = rng.uniform(0, 2 * math.pi)
        radial = Vector((math.cos(phi), math.sin(phi), 0))
        root = radial * (receptacle_profile(z) - 0.002) + Z * z
        strands.append(hair_strand(root, radial, Z, rng))
    return strands


def hair_strand(root, radial, towards, rng):
    """One stiff, spreading bristle, angled a little towards `towards` (along
    the stem, towards the flower) and curving slightly."""
    tilt = math.radians(rng.uniform(5, 60))
    direction = (radial * math.cos(tilt) + towards * math.sin(tilt)).normalized()
    length = rng.uniform(0.03, 0.085)
    bend = rng.uniform(-0.25, 0.35)
    pts = []
    for j in range(4):
        s = j / 3
        pts.append((root + direction * (length * s) + towards * (bend * length * s * s),
                    lerp(0.0009, 0.00015, s)))
    return pts


def stamen_geometry(t, rng_seed=7):
    """Filaments as hair strands and anthers as oblong ellipsoids, in
    head-local space, in three crowded rows around the pod."""
    rng = random.Random(rng_seed)
    spread = smoothstep(0.12, 0.85, t)
    strands, ant_v, ant_f = [], [], []
    count = 240
    for k in range(count):
        row = k % 3
        w = 2 * math.pi * k / count + rng.uniform(-0.02, 0.02)
        radial = Vector((math.cos(w), math.sin(w), 0))
        side = Vector((-radial.y, radial.x, 0))
        r0 = 0.034 + 0.005 * row
        tip_r = lerp(r0 + 0.012, rng.uniform(0.11, 0.17) + 0.015 * row, spread)
        tip_z = lerp(0.085 - 0.008 * row, rng.uniform(0.10, 0.145) - 0.012 * row, spread)
        sway = rng.uniform(-0.015, 0.015) * spread
        pts = []
        for j in range(6):
            s = j / 5
            zz = lerp(0.008, tip_z, math.sin(s * math.pi / 2))
            rr = max(lerp(r0, tip_r, s ** 1.5), pod_radius(zz) + 0.004)
            pts.append(radial * rr + Z * zz + side * (sway * s * s))
        strands.append([(p, lerp(0.0017, 0.0011, j / 5)) for j, p in enumerate(pts)])
        d = (pts[-1] - pts[-2]).normalized()
        half = rng.uniform(0.010, 0.014)
        add_ellipsoid(ant_v, ant_f, pts[-1] + d * (half * 0.8), d, half, rng.uniform(0.0042, 0.0052))
    return strands, (ant_v, ant_f)


def build_centre(head, mats):
    pod = new_object("Pod", head, mats["pod"])
    replace_mesh(pod, *pod_geometry())
    cap = new_object("Stigma", head, mats["stigma"])
    verts, faces, ray = cap_geometry()
    replace_mesh(cap, verts, faces, attrs={"ray": ray})
    rec = new_object("Receptacle", head, mats["stem"])
    replace_mesh(rec, *receptacle_geometry())
    replace_hair(new_hair("HeadHairs", mats["hair"], head), receptacle_hairs())
    return pod, cap


# ---------------------------------------------------------------- droplets

def make_petal_drops(rng_seed=5):
    """A fixed set of drops per petal, at petal coordinates (u, v), so each
    rides on its petal as it opens. Mostly small, a few large."""
    rng = random.Random(rng_seed)
    return [[(rng.uniform(0.25, 0.9), rng.uniform(-0.8, 0.8), 0.006 + 0.022 * rng.random() ** 2,
              rng.uniform(0.08, 0.3)) for _ in range(rng.randint(14, 22))] for _ in PETALS]


PETAL_DROPS = make_petal_drops()


def petal_drops(verts, drops, t, out_v, out_f):
    """Drops on the petal's inner face. On the back they show through the thin
    petal as dark stains, and in the tight bud they would poke through the
    neighbouring petals, so each one swells into view as the flower opens."""
    row = NV + 1
    for u, v, radius, appear in drops:
        size = smoothstep(appear, appear + 0.12, t)
        if size < 0.05:
            continue
        iu = min(max(round(u * NU), 1), NU - 1)
        iv = min(max(round((v + 1) / 2 * NV), 1), NV - 1)
        du = verts[(iu + 1) * row + iv] - verts[(iu - 1) * row + iv]
        dv = verts[iu * row + iv + 1] - verts[iu * row + iv - 1]
        nrm = du.cross(dv)  # points to the inner face
        if nrm.length > 1e-9:
            add_droplet(out_v, out_f, verts[iu * row + iv], nrm.normalized(), radius * size)


# -------------------------------------------------------------------- stem

STEM_R = 0.042


def stem_controls(head):
    """The stem's Bezier control points: from below the frame at the bottom
    left up into the receptacle, arriving along the head's axis."""
    top = head.matrix_world @ Vector((0, 0, -0.04))
    axis = (head.matrix_world.to_quaternion() @ Z).normalized()
    return Vector((-1.30, 0.30, -1.95)), Vector((-1.10, 0.25, -1.2)), top - axis * 0.8, top


def bezier(ctrl, s):
    p0, h0, h1, p1 = ctrl
    m = 1 - s
    pos = p0 * m ** 3 + h0 * (3 * m * m * s) + h1 * (3 * m * s * s) + p1 * s ** 3
    tan = (h0 - p0) * (3 * m * m) + (h1 - h0) * (6 * m * s) + (p1 - h1) * (3 * s * s)
    return pos, tan.normalized()


def update_stem(stem, ctrl):
    p0, p1 = stem.data.splines[0].bezier_points
    p0.co, p0.handle_right, p1.handle_left, p1.co = ctrl
    p0.handle_left = (-1.40, 0.30, -2.4)
    p1.handle_right = ctrl[3] + (ctrl[3] - ctrl[2]).normalized() * 0.1


def stem_hairs(ctrl, rng_seed=3, count=1800):
    rng = random.Random(rng_seed)
    strands = []
    for _ in range(count):
        s = rng.uniform(0.0, 0.99)
        phi = rng.uniform(0, 2 * math.pi)
        pos, tan = bezier(ctrl, s)
        a, b = basis(tan)
        radial = a * math.cos(phi) + b * math.sin(phi)
        strands.append(hair_strand(pos + radial * (STEM_R - 0.002), radial, tan, rng))
    return strands


def stem_drops(ctrl, out_v, out_f, rng_seed=9, count=30):
    rng = random.Random(rng_seed)
    for _ in range(count):
        s = rng.uniform(0.15, 0.96)
        # Mostly on the side facing the camera, where they catch the light.
        phi = math.pi / 2 + rng.uniform(-1.4, 1.4)
        radius = 0.009 + 0.018 * rng.random() ** 2
        pos, tan = bezier(ctrl, s)
        a, b = basis(tan)
        radial = a * math.cos(phi) + b * math.sin(phi)
        add_droplet(out_v, out_f, pos + radial * STEM_R, radial, radius, surface_r=STEM_R)


def build_stem(mat):
    curve = bpy.data.curves.new("Stem", "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = STEM_R
    curve.bevel_resolution = 6
    curve.resolution_u = 32
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(1)
    obj = bpy.data.objects.new("Stem", curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(mat)
    return obj


def head_rotation(t):
    """Head axis turns from sideways (bud) to facing the camera (full bloom),
    with a little roll so it reads as a twist rather than a pan."""
    side = Vector((0.80, 0.05, 0.60)).normalized()
    front = Vector((0.12, -1.0, 0.24)).normalized()  # tilted a little so the cup shows
    k = smoothstep(0.0, 1.0, ease(t))
    q_side = Z.rotation_difference(side)
    q_front = Z.rotation_difference(front)
    q = q_side.slerp(q_front, k)
    axis = q @ Z
    roll = Quaternion(axis, math.radians(lerp(0, 35, k)))
    return roll @ q


# ----------------------------------------------------------------------- main

def main():
    args = parse_args()
    os.makedirs(args.out, exist_ok=True)
    scene = reset_scene()
    setup_render(scene, args.res, args.samples)
    setup_world_and_backdrop(scene)
    setup_camera(scene)
    # Strong warm backlight from behind upper right, soft cool fill from the
    # front left. The backlights are relit per output level (setup_compositor).
    add_area_light("Key", (3.2, 0.0, 1.8), HEAD_POS, 950, 0.8, (1.0, 0.94, 0.86), "key")
    add_area_light("Back", (1.4, 3.0, 2.2), HEAD_POS, 900, 1.0, (1.0, 0.92, 0.84), "key")
    add_area_light("Rim", (-0.8, 2.8, 2.4), HEAD_POS, 300, 1.0, (1.0, 0.95, 0.9), "key")
    add_area_light("Fill", (-3.2, -4.0, 0.8), HEAD_POS, 12, 3.0, (0.80, 0.90, 1.0), "ambient")
    levels = {"dim": args.dim, "bright": args.bright}
    save = setup_compositor(scene, args.out, levels)

    mats = {
        "petal": petal_material(),
        "pod": grain_material("Pod", (0.10, 0.24, 0.035), (0.30, 0.42, 0.07), 900, roughness=0.55, sheen=0.3),
        "stigma": grain_material("Stigma", (0.22, 0.30, 0.04), (0.62, 0.52, 0.10), 700, roughness=0.6,
                                 attribute="ray"),
        "filament": simple_material("Filament", (0.62, 0.58, 0.14), roughness=0.4, subsurface=0.3,
                                    transmission=0.25),
        "anther": simple_material("Anther", (0.95, 0.74, 0.16), roughness=0.75, subsurface=0.25, sheen=0.4),
        "stem": simple_material("Stem", (0.045, 0.10, 0.035), roughness=0.8, sheen=0.12, specular=0.2),
        "hair": simple_material("Hair", (0.55, 0.62, 0.42), roughness=0.45, subsurface=0.2, transmission=0.5),
        "water": water_material(),
    }

    head = bpy.data.objects.new("Head", None)
    bpy.context.collection.objects.link(head)
    head.location = HEAD_POS
    head.rotation_mode = "QUATERNION"

    petals = []
    for i, spec in enumerate(PETALS):
        obj = new_object(f"Petal{i}", head, mats["petal"])
        sub = obj.modifiers.new("Subsurf", "SUBSURF")
        sub.levels = 1
        sub.render_levels = 1
        petals.append(obj)
    filaments = new_hair("Filaments", mats["filament"], head)
    anthers = new_object("Anthers", head, mats["anther"])
    petal_water = new_object("PetalDrops", head, mats["water"])
    pod, cap = build_centre(head, mats)
    stem = build_stem(mats["stem"])
    stem_hair = new_hair("StemHairs", mats["hair"])
    stem_water = new_object("StemDrops", None, mats["water"])

    # The open flower faces away from the backlight, which would leave its
    # centre in shadow. A soft light from the front, linked to the centre and
    # the water only, lights the stamens and puts a glint in each drop
    # without flattening the glowing petals.
    glint = add_area_light("Glint", (2.0, -3.2, 2.4), HEAD_FRONT, 160, 1.2, (1.0, 0.95, 0.88), "key")
    receivers = bpy.data.collections.new("Glint receivers")
    for obj in (pod, cap, filaments, anthers, petal_water, stem_water):
        receivers.objects.link(obj)
    glint.light_linking.receiver_collection = receivers

    if args.preview:
        values = [float(x) for x in args.preview.split(",")]
        names = [f"preview_{v:.2f}" for v in values]
    else:
        values = [i / (args.frames - 1) for i in range(args.start, args.frames)]
        names = [f"poppy_{i:03d}" for i in range(args.start, args.frames)]
        for level in levels:
            os.makedirs(os.path.join(args.out, level), exist_ok=True)

    for t, name in zip(values, names):
        head.rotation_quaternion = head_rotation(t)
        head.location = HEAD_SIDE.lerp(HEAD_FRONT, smoothstep(0.0, 1.0, ease(t)))
        bpy.context.view_layer.update()
        drop_v, drop_f = [], []
        for obj, spec, drops in zip(petals, PETALS, PETAL_DROPS):
            verts, faces, uvs, edge = petal_geometry(spec, t)
            replace_mesh(obj, verts, faces, uvs, {"edge": edge})
            petal_drops(verts, drops, t, drop_v, drop_f)
        replace_mesh(petal_water, drop_v, drop_f)
        strands, (av, af) = stamen_geometry(t)
        replace_hair(filaments, strands)
        replace_mesh(anthers, av, af)
        ctrl = stem_controls(head)
        update_stem(stem, ctrl)
        replace_hair(stem_hair, stem_hairs(ctrl))
        drop_v, drop_f = [], []
        stem_drops(ctrl, drop_v, drop_f)
        replace_mesh(stem_water, drop_v, drop_f)

        # The compositor saves <name>_<level>.jpg; full runs file each level
        # in its own folder under the frame's name.
        save.file_name = name + "_"
        bpy.ops.render.render()
        if not args.preview:
            for level in levels:
                os.replace(os.path.join(args.out, f"{name}_{level}.jpg"),
                           os.path.join(args.out, level, name + ".jpg"))
        print(f"rendered t={t:.3f} -> {name}", flush=True)


main()
