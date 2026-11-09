"""Procedural moth orchid (Phalaenopsis) for the CPU Bloom "orchid" theme,
rendered with Cycles.

One bloom parameter t in [0, 1] drives the whole pose, staged like a
timelapse of a bud opening:
  0     a closed, egg-shaped bud of three sepals hanging from its stalk
  0.45  the sepals part at the tip and the veined petals show
  0.75  sepals and petals unfurl, the lip and column come out
  1     fully open and facing the camera
Each output frame is one evenly spaced value of t, so the Processing theme can
scrub the sequence forwards and backwards. Every frame is saved twice, with a
dim and a bright backlight (out/dim/, out/bright/), and the theme blends the
two by CPU temperature.

Usually run through orchid/render.sh. Directly:
  blender -b --factory-startup -P orchid/orchid.py -- --preview 0,0.5,1 --res 640 --out /tmp/orchid
  blender -b --factory-startup -P orchid/orchid.py -- --frames 121 --res 1280 --out cpu_bloom/data/orchid
"""

import argparse
import bisect
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "blender"))
from common import (add_area_light, add_ellipsoid, clamp01, lerp, new_object,  # noqa: E402
                    node_material, replace_mesh, set_inputs, setup_compositor, setup_render, smoothstep)

Z = Vector((0, 0, 1))


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--preview", help="comma-separated t values to render instead of a sequence")
    p.add_argument("--frames", type=int, default=121, help="number of evenly spaced t values")
    p.add_argument("--start", type=int, default=0, help="first frame to render, to resume a stopped run")
    p.add_argument("--res", type=int, default=1280)
    p.add_argument("--samples", type=int, default=192)
    p.add_argument("--dim", type=float, default=0.4, help="backlight strength for a cool CPU")
    p.add_argument("--bright", type=float, default=1.3, help="backlight strength for a hot CPU")
    p.add_argument("--border", help="x0,y0,x1,y1: render only this part of the frame (0-1, y down), "
                                    "for close-ups during look development")
    p.add_argument("--out", required=True)
    return p.parse_args(argv)


# Stages of the opening, as (start, end) values of t. The bud swells, then
# turns to face the camera as it opens: the lateral sepals and the lip
# first, while the dorsal sepal and the petals still hood the top, as in
# the reference timelapse.
SWELL = (0.0, 0.30)
LATERAL = (0.20, 0.80)
DORSAL = (0.26, 0.90)
PETALS = (0.30, 0.97)
LIP = (0.26, 0.90)
TURN = (0.12, 0.75)


def stage(span, t):
    return smoothstep(span[0], span[1], t)


# ---------------------------------------------------------------- scene setup

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def setup_world(scene):
    """Pure black, as in a studio timelapse, so the theme's background is a
    flat black that the window extends seamlessly."""
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.lightgroup = "ambient"
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0, 0, 0, 1)
    bg.inputs["Strength"].default_value = 0.0


def setup_camera(scene):
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 92
    cam_data.sensor_width = 36
    cam_data.dof.use_dof = True
    cam_data.dof.aperture_fstop = 6.3
    cam_data.dof.focus_distance = 2.72
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, -2.72, 0.02)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    return cam


# ------------------------------------------------------------------ materials

def principled(name, color, **inputs):
    mat, nt, out = node_material(name)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    set_inputs(bsdf, **inputs)
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat, nt, bsdf


def math_node(nt, op, a=None, b=None, clamp=False):
    node = nt.nodes.new("ShaderNodeMath")
    node.operation = op
    node.use_clamp = clamp
    for i, x in enumerate((a, b)):
        if x is None:
            continue
        if isinstance(x, (int, float)):
            node.inputs[i].default_value = x
        else:
            nt.links.new(x, node.inputs[i])
    return node.outputs[0]


def map_range(nt, value, from_min, from_max, to_min=0.0, to_max=1.0, smooth=True):
    node = nt.nodes.new("ShaderNodeMapRange")
    if smooth:
        node.interpolation_type = "SMOOTHSTEP"
    set_inputs(node, From_Min=from_min, From_Max=from_max, To_Min=to_min, To_Max=to_max)
    nt.links.new(value, node.inputs["Value"])
    return node.outputs["Result"]


def mix_rgb(nt, fac, a, b, blend="MIX"):
    node = nt.nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    node.blend_type = blend
    node.clamp_factor = True
    for socket, x in ((node.inputs[0], fac), (node.inputs[6], a), (node.inputs[7], b)):
        if isinstance(x, (int, float)):
            socket.default_value = x
        elif isinstance(x, tuple):
            socket.default_value = (*x, 1) if len(x) == 3 else x
        else:
            nt.links.new(x, socket)
    return node.outputs[2]


def uv_parts(nt):
    """u (along the organ, 0 at its base) and the across coordinate in 0..1."""
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs["UV"], sep.inputs[0])
    return uv.outputs["UV"], sep.outputs["X"], sep.outputs["Y"]


def attribute(nt, name):
    node = nt.nodes.new("ShaderNodeAttribute")
    node.attribute_name = name
    return node.outputs["Fac"]


def vec(nt, x, y, z=0.0):
    node = nt.nodes.new("ShaderNodeCombineXYZ")
    for socket, value in zip(node.inputs, (x, y, z)):
        if isinstance(value, (int, float)):
            socket.default_value = value
        else:
            nt.links.new(value, socket)
    return node.outputs[0]


def sparkle_bump(nt, strength):
    """The waxy "diamond dust" of orchid tepals: a fine granular bump that
    glints under the key light."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grain = nt.nodes.new("ShaderNodeTexVoronoi")
    set_inputs(grain, Scale=520.0, Randomness=1.0)
    nt.links.new(tc.outputs["Object"], grain.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    set_inputs(bump, Strength=strength, Distance=0.0006)
    nt.links.new(grain.outputs["Distance"], bump.inputs["Height"])
    return bump.outputs["Normal"]


def finish_tissue(nt, out, colour, back_colour, normal, roughness, translucency, sss=0.35, sheen=0.08):
    """Principled tissue mixed with a translucent layer, so thin tepals glow
    when backlit. The back of each organ has its own colour (the outside of
    the bud), chosen by which side the ray hits. Sheen stays low: more
    draws a white fringe round every silhouette."""
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    col = mix_rgb(nt, geo.outputs["Backfacing"], colour, back_colour)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    set_inputs(bsdf, Roughness=roughness, Specular_IOR_Level=0.45, Subsurface_Weight=sss,
               Subsurface_Scale=0.006, Sheen_Weight=sheen, Sheen_Roughness=0.35)
    if "Subsurface Radius" in bsdf.inputs:
        bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.45, 0.8)
    nt.links.new(col, bsdf.inputs["Base Color"])
    nt.links.new(normal, bsdf.inputs["Normal"])
    trans = nt.nodes.new("ShaderNodeBsdfTranslucent")
    glow = mix_rgb(nt, 1.0, col, (1.0, 0.72, 0.92), "MULTIPLY")
    nt.links.new(glow, trans.inputs["Color"])
    nt.links.new(normal, trans.inputs["Normal"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    # The outside of the bud is thick and nearly opaque.
    nt.links.new(math_node(nt, "MULTIPLY", translucency,
                           math_node(nt, "SUBTRACT", 1.0, math_node(nt, "MULTIPLY", geo.outputs["Backfacing"], 0.75))),
                 mix.inputs["Fac"])
    nt.links.new(bsdf.outputs[0], mix.inputs[1])
    nt.links.new(trans.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def tepal_material():
    """White with a lilac flush towards the rim, fine violet veins fanning
    from the base that fork and fade into a net, and small dark crimson
    dots where the `spot` attribute asks for them (the lateral sepals)."""
    mat, nt, out = node_material("Tepal")
    _, u, w = uv_parts(nt)
    seed = attribute(nt, "seed")

    # Main veins: thin peaks of a distorted wave running base to tip. The
    # across coordinate already fans out from the narrow base. Two waves
    # that wander apart read as veins forking.
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    set_inputs(wave, Scale=6.0, Distortion=4.0, Detail=1.5, Detail_Scale=2.0, Detail_Roughness=0.5)
    nt.links.new(vec(nt, w, math_node(nt, "MULTIPLY", u, 0.35), seed), wave.inputs["Vector"])
    main = map_range(nt, wave.outputs["Fac"], 0.84, 0.97)
    side = nt.nodes.new("ShaderNodeTexWave")
    side.wave_type = "BANDS"
    side.bands_direction = "X"
    set_inputs(side, Scale=6.0, Distortion=8.0, Detail=2.0, Detail_Scale=2.0, Detail_Roughness=0.5)
    nt.links.new(vec(nt, w, math_node(nt, "MULTIPLY", u, 0.6), math_node(nt, "ADD", seed, 17.0)),
                 side.inputs["Vector"])
    fork = map_range(nt, side.outputs["Fac"], 0.86, 0.97)
    # Forks appear from a third of the way out, not at the base.
    main = math_node(nt, "MAXIMUM", main, math_node(nt, "MULTIPLY", fork, map_range(nt, u, 0.25, 0.6, 0.0, 0.85)))
    # Veins darken and fade along their length rather than staying even.
    strength = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(strength, Scale=1.0, Detail=2.0)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", w, 6.0), math_node(nt, "MULTIPLY", u, 2.5), seed),
                 strength.inputs["Vector"])
    main = math_node(nt, "MULTIPLY", main, map_range(nt, strength.outputs["Fac"], 0.3, 0.6, 0.45, 1.0))

    # The finer net between them: Voronoi cell edges, stretched along the
    # tepal, strongest towards the rim.
    net = nt.nodes.new("ShaderNodeTexVoronoi")
    net.feature = "DISTANCE_TO_EDGE"
    set_inputs(net, Scale=1.0, Randomness=0.9)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", w, 60.0), math_node(nt, "MULTIPLY", u, 26.0), seed),
                 net.inputs["Vector"])
    fine = math_node(nt, "MULTIPLY", map_range(nt, net.outputs["Distance"], 0.05, 0.0),
                     map_range(nt, u, 0.25, 0.9, 0.3, 0.75))
    veins = math_node(nt, "MAXIMUM", main, fine)
    # Veins start a little out from the base, which stays white.
    veins = math_node(nt, "MULTIPLY", veins, map_range(nt, u, 0.04, 0.22))

    rim = math_node(nt, "ABSOLUTE", math_node(nt, "SUBTRACT", math_node(nt, "MULTIPLY", w, 2.0), 1.0))
    flush = math_node(nt, "MAXIMUM", map_range(nt, u, 0.45, 1.0), map_range(nt, rim, 0.55, 1.0, 0.0, 0.7))
    ground = mix_rgb(nt, math_node(nt, "MULTIPLY", flush, 0.8), (0.91, 0.85, 0.92), (0.70, 0.42, 0.80))
    # Soft blotches of deeper colour, so no two tepals are evenly tinted.
    blotch = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(blotch, Scale=3.0, Detail=2.0)
    nt.links.new(vec(nt, w, u, seed), blotch.inputs["Vector"])
    ground = mix_rgb(nt, map_range(nt, blotch.outputs["Fac"], 0.5, 0.75, 0.0, 0.25), ground, (0.62, 0.42, 0.82))
    # A pink flush right at the base, round the column.
    ground = mix_rgb(nt, map_range(nt, u, 0.10, 0.0, 0.0, 0.55), ground, (0.78, 0.30, 0.60))
    colour = mix_rgb(nt, math_node(nt, "MULTIPLY", veins, 0.95), ground, (0.32, 0.02, 0.40))
    # "Diamond dust": the glistening cells of the surface, as pale flecks.
    tc = nt.nodes.new("ShaderNodeTexCoord")
    grain = nt.nodes.new("ShaderNodeTexVoronoi")
    set_inputs(grain, Scale=520.0, Randomness=1.0)
    nt.links.new(tc.outputs["Object"], grain.inputs["Vector"])
    colour = mix_rgb(nt, map_range(nt, grain.outputs["Distance"], 0.22, 0.08, 0.0, 0.3), colour, (1.0, 0.96, 1.0))

    # Dots: Voronoi cells, each kept or dropped at random so they scatter
    # unevenly, densest near the base and thinning out by mid-sepal.
    spots = nt.nodes.new("ShaderNodeTexVoronoi")
    set_inputs(spots, Scale=1.0, Randomness=1.0)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", w, 22.0), math_node(nt, "MULTIPLY", u, 20.0), seed),
                 spots.inputs["Vector"])
    keep = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(spots.outputs["Color"], keep.inputs[0])
    density = map_range(nt, u, 0.80, 0.10)
    kept = math_node(nt, "LESS_THAN", keep.outputs[0], density)
    dot = map_range(nt, spots.outputs["Distance"], 0.26, 0.18)
    dots = math_node(nt, "MULTIPLY", math_node(nt, "MULTIPLY", dot, kept),
                     math_node(nt, "MULTIPLY", attribute(nt, "spot"), map_range(nt, u, 0.03, 0.10)))
    colour = mix_rgb(nt, dots, colour, (0.17, 0.01, 0.20))

    # Outside of the bud: cream, greening towards the stalk, with broad soft
    # mauve streaks down the middle of each sepal and a dusky tip.
    streak = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(streak, Scale=1.0, Detail=3.0, Roughness=0.55)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", w, 7.0), math_node(nt, "MULTIPLY", u, 0.9), seed),
                 streak.inputs["Vector"])
    middle = map_range(nt, rim, 0.98, 0.78)
    mauve = math_node(nt, "MULTIPLY", map_range(nt, streak.outputs["Fac"], 0.35, 0.60, 0.5, 1.0),
                      math_node(nt, "MULTIPLY", middle, map_range(nt, u, 0.12, 0.6)))
    back = mix_rgb(nt, map_range(nt, u, 0.0, 0.8), (0.46, 0.40, 0.30), (0.52, 0.38, 0.34))
    back = mix_rgb(nt, mauve, back, (0.40, 0.13, 0.22))
    back = mix_rgb(nt, map_range(nt, u, 0.88, 1.0, 0.0, 0.7), back, (0.30, 0.06, 0.20))
    back = mix_rgb(nt, map_range(nt, u, 0.14, 0.02), back, (0.22, 0.34, 0.08))
    finish_tissue(nt, out, colour, back, sparkle_bump(nt, 0.14), roughness=0.5, translucency=0.28)
    return mat


def lip_material():
    """The lip as in the reference: side lobes white inside with rows of
    crimson dashes running up to magenta rims, a yellow floor under the
    callus, and a glossy crimson-magenta midlobe with a spotted yellow
    streak down its middle. Magenta outside. Deep wine while emerging."""
    mat, nt, out = node_material("Lip")
    _, u, w = uv_parts(nt)
    across = math_node(nt, "ABSOLUTE", math_node(nt, "SUBTRACT", math_node(nt, "MULTIPLY", w, 2.0), 1.0))
    midlobe = map_range(nt, u, 0.46, 0.56)

    # Side lobes: white to pink inside, magenta towards the rim.
    lobe = mix_rgb(nt, map_range(nt, across, 0.25, 0.75), (0.92, 0.80, 0.70), (0.90, 0.66, 0.78))
    lobe = mix_rgb(nt, map_range(nt, across, 0.62, 0.95), lobe, (0.50, 0.0, 0.22))
    # Deep inside, near the lip's base, it darkens to crimson.
    lobe = mix_rgb(nt, math_node(nt, "MULTIPLY", map_range(nt, u, 0.22, 0.04), map_range(nt, across, 0.75, 0.3)),
                   lobe, (0.20, 0.0, 0.04))
    # Crimson dashes, long across the lobe (from its floor up to its rim)
    # and in rows along it, kept at random so the rows are broken.
    dashes = nt.nodes.new("ShaderNodeTexVoronoi")
    set_inputs(dashes, Scale=1.0, Randomness=0.8)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", w, 30.0), math_node(nt, "MULTIPLY", u, 56.0)),
                 dashes.inputs["Vector"])
    keep = nt.nodes.new("ShaderNodeRGBToBW")
    nt.links.new(dashes.outputs["Color"], keep.inputs[0])
    dash = math_node(nt, "MULTIPLY", map_range(nt, dashes.outputs["Distance"], 0.42, 0.28),
                     math_node(nt, "LESS_THAN", keep.outputs[0], 0.95))
    dash = math_node(nt, "MULTIPLY", dash, map_range(nt, across, 0.18, 0.32))
    dash = math_node(nt, "MULTIPLY", dash, map_range(nt, across, 0.90, 0.70))
    lobe = mix_rgb(nt, dash, lobe, (0.30, 0.0, 0.04))
    # The floor between the side lobes, under the callus: yellow, streaked red.
    floor = math_node(nt, "MULTIPLY", map_range(nt, across, 0.30, 0.12), map_range(nt, u, 0.12, 0.30))
    floor_col = mix_rgb(nt, math_node(nt, "MULTIPLY", dash, 0.8), (0.95, 0.60, 0.06), (0.55, 0.03, 0.02))
    lobe = mix_rgb(nt, floor, lobe, floor_col)

    # Midlobe: crimson-magenta, deeper at the tip, with a yellow streak at
    # its base spotted red.
    mid = mix_rgb(nt, map_range(nt, u, 0.55, 1.0), (0.55, 0.0, 0.12), (0.40, 0.0, 0.20))
    spots = nt.nodes.new("ShaderNodeTexVoronoi")
    set_inputs(spots, Scale=1.0, Randomness=1.0)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", w, 40.0), math_node(nt, "MULTIPLY", u, 50.0)),
                 spots.inputs["Vector"])
    streak_col = mix_rgb(nt, map_range(nt, spots.outputs["Distance"], 0.24, 0.14), (0.98, 0.66, 0.06),
                         (0.55, 0.03, 0.02))
    streak = math_node(nt, "MULTIPLY", map_range(nt, across, 0.20, 0.06), map_range(nt, u, 0.78, 0.55))
    mid = mix_rgb(nt, streak, mid, streak_col)

    colour = mix_rgb(nt, midlobe, lobe, mid)
    # While it is still emerging the lip is a deep wine colour; it brightens
    # to magenta as the flower finishes opening (`open` is the organ's
    # openness).
    colour = mix_rgb(nt, map_range(nt, attribute(nt, "open"), 0.95, 0.55, 0.0, 0.8), colour, (0.20, 0.0, 0.06))
    back = mix_rgb(nt, map_range(nt, u, 0.2, 0.6), (0.48, 0.0, 0.25), (0.44, 0.0, 0.17))
    finish_tissue(nt, out, colour, back, sparkle_bump(nt, 0.03), roughness=0.30, translucency=0.16,
                  sss=0.45, sheen=0.06)
    return mat


def callus_material():
    """Golden yellow, orange at its base, with red-brown spots."""
    mat, nt, out = node_material("Callus")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    spots = nt.nodes.new("ShaderNodeTexVoronoi")
    set_inputs(spots, Scale=170.0, Randomness=1.0)
    nt.links.new(tc.outputs["Object"], spots.inputs["Vector"])
    base = mix_rgb(nt, attribute(nt, "height"), (0.92, 0.34, 0.02), (1.0, 0.68, 0.05))
    colour = mix_rgb(nt, map_range(nt, spots.outputs["Distance"], 0.34, 0.24), base, (0.40, 0.03, 0.02))
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    set_inputs(bsdf, Roughness=0.38, Specular_IOR_Level=0.45, Subsurface_Weight=0.4, Subsurface_Scale=0.003)
    nt.links.new(colour, bsdf.inputs["Base Color"])
    nt.links.new(sparkle_bump(nt, 0.08), bsdf.inputs["Normal"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def stem_material(name, colour_a, colour_b, roughness, node_colour=None, scale=6.0, young_colour=None,
                  speckle=None, streak=0.15):
    """Mottled stalk tissue along the tube's length (UV x), with fine
    lengthwise streaks. The `node` attribute blends in node_colour (the
    collar at a node) and the `young` attribute young_colour; speckle adds
    fine flecks of that colour where the stalk is old."""
    mat, nt, out = node_material(name)
    uv, u, w = uv_parts(nt)
    mottle = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(mottle, Scale=scale, Detail=4.0, Roughness=0.6)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", u, 4.0), math_node(nt, "MULTIPLY", w, 0.6)),
                 mottle.inputs["Vector"])
    colour = mix_rgb(nt, map_range(nt, mottle.outputs["Fac"], 0.35, 0.65), colour_a, colour_b)
    if young_colour:
        colour = mix_rgb(nt, attribute(nt, "young"), colour, young_colour)
    if speckle:
        # UV x runs 3 per scene unit and y once round the tube, so this
        # makes round flecks about 2 mm across.
        flecks = nt.nodes.new("ShaderNodeTexVoronoi")
        set_inputs(flecks, Scale=1.0, Randomness=1.0)
        nt.links.new(vec(nt, math_node(nt, "MULTIPLY", u, 150.0), math_node(nt, "MULTIPLY", w, 45.0)),
                     flecks.inputs["Vector"])
        fleck = map_range(nt, flecks.outputs["Distance"], 0.22, 0.12)
        if young_colour:
            fleck = math_node(nt, "MULTIPLY", fleck, math_node(nt, "SUBTRACT", 1.0, attribute(nt, "young")))
        colour = mix_rgb(nt, math_node(nt, "MULTIPLY", fleck, 0.6), colour, speckle)
    if node_colour:
        colour = mix_rgb(nt, attribute(nt, "node"), colour, node_colour)
    streaks = nt.nodes.new("ShaderNodeTexNoise")
    set_inputs(streaks, Scale=1.0, Detail=2.0)
    nt.links.new(vec(nt, math_node(nt, "MULTIPLY", u, 3.0), math_node(nt, "MULTIPLY", w, 90.0)),
                 streaks.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    set_inputs(bump, Strength=streak, Distance=0.001)
    nt.links.new(streaks.outputs["Fac"], bump.inputs["Height"])
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    set_inputs(bsdf, Roughness=roughness, Specular_IOR_Level=0.32, Subsurface_Weight=0.15,
               Subsurface_Scale=0.004, Sheen_Weight=0.04, Sheen_Roughness=0.5)
    nt.links.new(colour, bsdf.inputs["Base Color"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def column_material():
    mat, nt, bsdf = principled("Column", (0.70, 0.20, 0.45), Roughness=0.34, Subsurface_Weight=0.5,
                               Subsurface_Scale=0.005, Sheen_Weight=0.05)
    return mat


def anther_material():
    mat, nt, bsdf = principled("Anther", (0.96, 0.80, 0.72), Roughness=0.45, Subsurface_Weight=0.3,
                               Subsurface_Scale=0.003)
    return mat


# ------------------------------------------------------------------- geometry

# Scene units: the open flower is about 1 across and the bud about 0.3 long.
# The bud hangs just right of centre; the open flower faces the camera in
# the middle of the frame.
HEAD_BUD = Vector((0.09, 0.0, -0.01))
HEAD_OPEN = Vector((0.0, 0.0, 0.02))
BUD_AXIS = Vector((0.62, -0.22, -0.75)).normalized()   # bud tip points down and right
OPEN_AXIS = Vector((0.03, -1.0, 0.10)).normalized()    # faces the camera, a little upward

# The closed bud: an egg with its broad end at the stalk.
BUD_H, BUD_R, BUD_R0 = 0.31, 0.116, 0.026


def bud_radius(zz):
    return BUD_R * math.sin(math.pi * zz ** 0.85) ** 0.4 * (1 - 0.12 * zz) + BUD_R0 * (1 - zz) ** 2


def bud_meridian(rs, hs, n=240):
    """The bud's profile scaled by rs (radius) and hs (height), as samples of
    (arc fraction, angle from the axis, radius), and its length."""
    pts = [(bud_radius(i / n) * rs, i / n * BUD_H * hs) for i in range(n + 1)]
    arc = [0.0]
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        arc.append(arc[-1] + math.hypot(r1 - r0, z1 - z0))
    total = arc[-1]
    samples = []
    for i in range(n):
        (r0, z0), (r1, z1) = pts[i], pts[i + 1]
        samples.append(((arc[i] + arc[i + 1]) / 2 / total, math.atan2(r1 - r0, z1 - z0), (r0 + r1) / 2))
    return samples, total


def table(samples, s, k):
    """Linear interpolation in a list of (s, ...) tuples, of field k."""
    if s <= samples[0][0]:
        return samples[0][k]
    for a, b in zip(samples, samples[1:]):
        if s <= b[0]:
            f = (s - a[0]) / (b[0] - a[0])
            return a[k] + (b[k] - a[k]) * f
    return samples[-1][k]


def outline(u, w_max, c, base, p_lo=2.0, p_hi=2.0):
    """Half-width along an organ: a narrow claw of half-width `base` at u=0,
    widest (w_max) at u=c, closing round at the tip."""
    if u < c:
        x = (c - u) / c
        return base + (w_max - base) * max(0.0, 1 - x ** p_lo) ** (1 / p_lo)
    x = (u - c) / (1 - c)
    return w_max * max(0.0, 1 - x ** p_hi) ** (1 / p_hi)


def lip_outline(u):
    """Three-lobed lip: broad side lobes, a narrow isthmus, then an
    anchor-shaped midlobe: two wings, then a strap out to the tip, where
    the tendrils are."""
    side = 0.30 * math.sin(math.pi * clamp01(u / 0.52)) ** 0.35
    wings = 0.095 * math.sin(math.pi * clamp01((u - 0.48) / 0.34)) ** 0.8 if u > 0.48 else 0.0
    strap = 0.034 * smoothstep(0.55, 0.70, u) * (1 - smoothstep(0.94, 1.0, u))
    return max(side, wings, strap, 0.04 * (1 - u) + 0.008)


def lip_cup(u):
    """The side lobes curl up round the column, so from the front the lip
    is a magenta-rimmed hoop that you look into; the midlobe's wings bend
    back a little."""
    return lerp(155, -12, smoothstep(0.42, 0.60, u))


def make_organs():
    """Three sepals (dorsal, two lateral), two broad petals and the lip.
    gamma is the direction in the face of the flower (0 = up, 90 = right).
    Sepals sit behind the petals and the lip in front, so the open flower
    layers like the real one; in the bud the same order nests them, sepals
    outermost."""
    rng = random.Random(21)
    organs = []

    def add(name, gamma, length, w, c, base, p_lo, p_hi, a_open, bend, cup, rs, hs, psi_bud,
            span, z0, spot=0.0, keel=0.006, ruffle=0.004, r_open=0.03, bend_from=0.0):
        meridian, bud_len = bud_meridian(rs, hs)
        organs.append({
            "name": name, "gamma": gamma + rng.uniform(-2, 2), "length": length * rng.uniform(0.97, 1.03),
            "outline": (lambda u, w=w, c=c, base=base, p_lo=p_lo, p_hi=p_hi: outline(u, w, c, base, p_lo, p_hi))
            if w else lip_outline,
            "cup": (lambda u, cup=cup: cup) if cup is not None else lip_cup,
            "a_open": a_open, "bend": bend, "rs": rs, "psi_bud": math.radians(psi_bud),
            "meridian": meridian, "bud_len": bud_len, "span": span, "z0": z0, "spot": spot,
            "keel": keel, "ruffle": ruffle, "r_open": r_open, "bend_from": bend_from, "seed": rng.uniform(0, 100),
        })

    # name, gamma, length, half width, widest at, claw, tip shape, open angle, tip bend,
    # cup, bud radius/height scale, bud wrap, stage, forward offset
    add("Dorsal", 0, 0.42, 0.100, 0.52, 0.020, 2.0, 1.7, 94, 6, 14, 1.0, 1.0, 61, DORSAL, 0.0)
    add("SepalL", -146, 0.41, 0.112, 0.46, 0.022, 2.0, 1.7, 94, 4, 14, 1.0, 1.0, 61, LATERAL, 0.0, spot=1.0)
    add("SepalR", 146, 0.41, 0.112, 0.46, 0.022, 2.0, 1.7, 94, 4, 14, 1.0, 1.0, 61, LATERAL, 0.0, spot=1.0)
    add("PetalL", -72, 0.45, 0.195, 0.58, 0.012, 1.6, 2.1, 86, 5, 10, 0.86, 0.92, 56, PETALS, 0.006,
        keel=0.003, ruffle=0.009)
    add("PetalR", 72, 0.45, 0.195, 0.58, 0.012, 1.6, 2.1, 86, 5, 10, 0.86, 0.92, 56, PETALS, 0.006,
        keel=0.003, ruffle=0.009)
    # The lip starts below the centre and points at the camera, its side lobes
    # curled up round the column, then the midlobe turns down.
    add("Lip", 180, 0.44, None, None, None, None, None, 12, 80, None, 0.5, 0.6, 110, LIP, 0.03,
        keel=0.0, ruffle=0.003, r_open=0.10, bend_from=0.42)
    return organs


ORGANS = make_organs()
NU, NV = 56, 72


def organ_frame(gamma):
    g = math.radians(gamma)
    e = Vector((math.sin(g), math.cos(g), 0))   # outwards in the face, towards the organ's tip
    et = Vector((math.cos(g), -math.sin(g), 0))  # across it, so et x e faces the front
    return e, et


def organ_geometry(spec, t, scale=1.0):
    """The organ's surface in the head's frame (+Z out of the flower's face).

    Its centreline lies in the plane of the flower's axis and the organ's
    direction e. In the bud it follows the egg's profile and each sepal wraps
    a third of the way round the axis; open, it lies nearly flat, cupped a
    little, with a waved rim. Between the two, the angle along the centreline
    and the curvature across it are interpolated and the centreline is
    integrated, so the organ keeps its length as it unfurls."""
    tp = stage(spec["span"], t)
    g = smoothstep(0.0, 1.0, tp)
    e, et = organ_frame(spec["gamma"])
    length = lerp(spec["bud_len"], spec["length"], g) * scale
    meridian = spec["meridian"]
    a_open = math.radians(spec["a_open"])
    bend = math.radians(spec["bend"])
    seed = spec["seed"]

    n = 160
    centre, inward = [], []
    p = e * (lerp(BUD_R0 * spec["rs"], spec["r_open"], g) * scale) + Z * (spec["z0"] * g * scale)
    for i in range(n + 1):
        s = i / n
        bent = max(0.0, s - spec["bend_from"]) / (1 - spec["bend_from"])
        a = lerp(table(meridian, s, 1), a_open + bend * bent * bent, g)
        tangent = math.cos(a) * Z + math.sin(a) * e
        centre.append(p.copy())
        inward.append(math.sin(a) * Z - math.cos(a) * e)
        p = p + tangent * (length / n)

    verts, uvs, edge = [], [], []
    for iu in range(NU + 1):
        u = iu / NU
        c = centre[round(u * n)]
        nin = inward[round(u * n)]
        r_bud = max(table(meridian, u, 2), 0.004) * scale
        w_bud = spec["psi_bud"] * r_bud
        w_open = max(spec["outline"](u) * scale, 0.002)
        w = lerp(w_bud, w_open, g)
        # Curvature across the organ: wrapped round the axis in the bud,
        # a shallow cup when open.
        kappa = lerp(1 / r_bud, math.radians(spec["cup"](u)) / w_open, g ** 0.8)
        for iv in range(NV + 1):
            v = iv / NV * 2 - 1
            xt = v * w
            psi = kappa * xt
            across = et * (math.sin(psi) / kappa) + nin * ((1 - math.cos(psi)) / kappa)
            q = Vector((u * 2.5, v * 1.6, seed))
            # In the bud, a raised keel down each sepal and grooves at the
            # seams; open, a faint midrib, waved edges and soft unevenness.
            keel = spec["keel"] * (1 - 0.7 * g) * (math.exp(-(v / 0.28) ** 2) - 0.8 * abs(v) ** 6)
            wave = spec["ruffle"] * g * smoothstep(0.35, 1.0, u) * abs(v) ** 1.5 \
                * math.sin(v * 7.0 + u * 9.0 + seed + 2.0 * noise.noise(q))
            lumpy = 0.004 * g * u * noise.noise(q * 1.7)
            verts.append(c + across + nin * (-keel + wave + lumpy) * scale)
            uvs.append((u, (v + 1) / 2))
            edge.append((1 - abs(v)) * w)
    faces = []
    row = NV + 1
    for iu in range(NU):
        for iv in range(NV):
            a = iu * row + iv
            faces.append((a, a + 1, a + row + 1, a + row))
    def at(u):
        """Point on the centreline at u, its inward normal, and the organ's
        outward and across directions."""
        return centre[round(u * n)], inward[round(u * n)], e, et

    attrs = {"spot": [spec["spot"]] * len(verts), "seed": [seed] * len(verts), "open": [g] * len(verts)}
    return verts, faces, uvs, attrs, at


# ----------------------------------------------------------- tubes and stems

def smooth_path(points, n):
    """n+1 points along a Catmull-Rom spline through `points`."""
    pts = [points[0] * 2 - points[1]] + list(points) + [points[-1] * 2 - points[-2]]
    segs = len(points) - 1
    out = []
    for i in range(n + 1):
        f = i / n * segs
        k = min(int(f), segs - 1)
        s = f - k
        p0, p1, p2, p3 = pts[k:k + 4]
        out.append(0.5 * (2 * p1 + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s
                          + (3 * p1 - p0 - 3 * p2 + p3) * s ** 3))
    return out


def bezier_path(p0, h0, h1, p1, n):
    out = []
    for i in range(n + 1):
        s = i / n
        m = 1 - s
        out.append(p0 * m ** 3 + h0 * (3 * m * m * s) + h1 * (3 * m * s * s) + p1 * s ** 3)
    return out


def tube(path, radius, segs=20, ribs=0, rib_depth=0.0, attr=None, verts=None, faces=None, uvs=None, attrs=None):
    """A tube along a polyline, with rotation-minimising frames so it never
    twists. radius(s) gives the radius at arc fraction s; ribs adds that
    many lengthwise ridges, rib_depth(s) deep (or a constant). Appends to the
    given lists."""
    verts = [] if verts is None else verts
    faces = [] if faces is None else faces
    uvs = [] if uvs is None else uvs
    attrs = [] if attrs is None else attrs
    tangents = []
    for i in range(len(path)):
        a, b = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        tangents.append((b - a).normalized())
    normal = tangents[0].cross(Vector((0, 1, 0)))
    if normal.length < 1e-6:
        normal = tangents[0].cross(Vector((1, 0, 0)))
    normal.normalize()
    arc = [0.0]
    for a, b in zip(path, path[1:]):
        arc.append(arc[-1] + (b - a).length)
    start = len(verts)
    for i, p in enumerate(path):
        if i:
            # Parallel transport the normal to the new tangent.
            normal = (normal - tangents[i] * normal.dot(tangents[i])).normalized()
        binormal = tangents[i].cross(normal)
        s = arc[i] / arc[-1]
        r = radius(s)
        depth = rib_depth(s) if callable(rib_depth) else rib_depth
        for j in range(segs + 1):
            phi = 2 * math.pi * j / segs
            rr = r * (1 + depth * math.cos(ribs * phi)) if ribs else r
            verts.append(p + (normal * math.cos(phi) + binormal * math.sin(phi)) * rr)
            uvs.append((arc[i] * 3.0, j / segs))
            attrs.append(attr(s) if attr else 0.0)
    row = segs + 1
    for i in range(len(path) - 1):
        for j in range(segs):
            a = start + i * row + j
            faces.append((a, a + row, a + row + 1, a + 1))
    return verts, faces, uvs, attrs


def finish_tube_mesh(obj, verts, faces, uvs, attrs, name="node"):
    replace_mesh(obj, verts, faces, uvs, {name: attrs})


# The flower spike, as points it passes through: in from below the frame at
# the bottom right, behind the bud, to a node at the left where the flower's
# stalk branches off, then up and out of the frame at the top left, with a
# second node carrying the spare bud.
SPIKE = [Vector(p) for p in ((0.62, 0.42, -0.95), (0.40, 0.30, -0.52), (0.08, 0.18, -0.24),
                             (-0.40, 0.08, -0.02), (-0.60, 0.10, 0.22), (-0.80, 0.14, 0.56))]
NODE = Vector((-0.40, 0.08, -0.02))
NODE2 = Vector((-0.60, 0.10, 0.22))
SPIKE_R = 0.016
PEDICEL_R = 0.013


def spike_geometry():
    """The spike and its `node` and `young` attributes: a red-brown collar
    at each node, green below the flower's node where the spike is young,
    and olive-brown and speckled above it, as in the reference."""
    path = smooth_path(SPIKE, 160)
    near = [min((p - NODE).length, (p - NODE2).length) for p in path]
    # tube() passes arc fractions, and spline points aren't evenly spaced.
    arc = [0.0]
    for a, b in zip(path, path[1:]):
        arc.append(arc[-1] + (b - a).length)
    fraction = [x / arc[-1] for x in arc]

    def near_at(s):
        return near[min(bisect.bisect_left(fraction, s), len(path) - 1)]

    def radius(s):
        return SPIKE_R * (1 + 0.22 * math.exp(-(near_at(s) / 0.025) ** 2))

    def node(s):
        return math.exp(-(near_at(s) / 0.022) ** 4)

    verts, faces, uvs, nodes = tube(path, radius, segs=24, attr=node)
    young = [smoothstep(NODE.z + 0.04, NODE.z - 0.10, v.z) for v in verts]
    return verts, faces, uvs, {"node": nodes, "young": young}


def pedicel_path(base, axis):
    """From the node, rising gently to the right, then hooking over into
    the back of the flower along its axis; the last stretch is the ovary."""
    leave = Vector((0.80, -0.12, 0.58)).normalized()
    return bezier_path(NODE, NODE + leave * 0.24, base - axis * 0.20, base, 90)


def pedicel_geometry(base, axis):
    def radius(s):
        # Leaves the node in a collar, then thickens into the ovary, which
        # flares into the base of the flower.
        return PEDICEL_R * (1 + 0.25 * math.exp(-(s / 0.03) ** 2) + 0.35 * smoothstep(0.78, 0.95, s)
                            + 0.6 * smoothstep(0.95, 1.0, s) ** 2)

    def flush(s):
        # The red-brown collar at the node, and a ruddy flush where the
        # stalk hooks over into the ovary.
        return max(math.exp(-(s / 0.025) ** 2), 0.65 * smoothstep(0.70, 0.92, s))

    return tube(pedicel_path(base, axis), radius, segs=24, ribs=6,
                rib_depth=lambda s: 0.05 * smoothstep(0.80, 0.95, s), attr=flush)


def column_geometry(t):
    """The column: a slender club that leaves the centre at the top of the
    lip's hoop and arches out towards the camera inside it, dipping at the
    tip, with the anther cap under its rounded end. Both ends are closed."""
    g = stage(LIP, t)
    k = lerp(0.45, 1.0, g) * 1.4
    path = bezier_path(Vector((0, 0.032, -0.003)) * k, Vector((0, 0.036, 0.036)) * k,
                       Vector((0, 0.030, 0.072)) * k, Vector((0, -0.014, 0.080)) * k, 24)
    verts, faces, uvs, _ = tube(path, lambda s: (0.013 + 0.006 * s ** 1.5) * k, segs=20)
    cap = len(verts)
    tip_dir = (path[-1] - path[-2]).normalized()
    add_ellipsoid(verts, faces, path[-1], tip_dir, 0.014 * k, 0.019 * k, rings=8, segs=20)
    base_dir = (path[0] - path[1]).normalized()
    add_ellipsoid(verts, faces, path[0], base_dir, 0.010 * k, 0.013 * k, rings=6, segs=20)
    # A rounded base where the column meets the tepals, closing the gap
    # between their bases in the middle of the flower.
    add_ellipsoid(verts, faces, Vector((0, 0.004, -0.012)), Z, 0.012 * k, 0.022 * k, rings=6, segs=20)
    uvs += [(1.0, 0.5)] * (len(verts) - cap)
    # The anther cap sits on the front of the tip, facing down and out.
    under = (tip_dir + Vector((0, 0, 0.8))).normalized()
    anther_v, anther_f = [], []
    add_ellipsoid(anther_v, anther_f, path[-1] + under * 0.012 * k, under, 0.008 * k, 0.012 * k,
                  rings=8, segs=14)
    return (verts, faces, uvs), (anther_v, anther_f)


def callus_geometry(at, t):
    """The callus on the lip's floor at the base of the midlobe: a ridge
    along the lip and two horns rising from it towards the column. Its
    `height` attribute (0 at the lip, 1 at the horn tips) shades it from
    orange to yellow."""
    g = stage(LIP, t)
    k = lerp(0.5, 1.0, g) * 1.8
    c, nin, e, et = at(0.47)
    along = nin.cross(et).normalized()
    verts, faces = [], []
    add_ellipsoid(verts, faces, c + nin * 0.005 * k, along, 0.022 * k, 0.012 * k, rings=8, segs=14)
    for side in (-1, 1):
        axis = (nin * 0.9 + et * (0.45 * side) - along * 0.2).normalized()
        add_ellipsoid(verts, faces, c + nin * 0.014 * k + et * (0.009 * side) * k, axis, 0.017 * k, 0.0098 * k,
                      rings=8, segs=12)
    height = [clamp01((v - c).dot(nin) / (0.03 * k)) for v in verts]
    return verts, faces, {"height": height}


def cirri_geometry(tip, t):
    """Two short tendrils curling from the tip of the lip's midlobe."""
    g = stage(LIP, t)
    c, nin, e, et = tip
    tangent = (c - c + nin.cross(et)).normalized()
    verts, faces, uvs, attrs = [], [], [], []
    for side in (-1, 1):
        pts = []
        for i in range(13):
            s = i / 12
            ang = s * 2.2 * g
            pts.append(c + et * (side * (0.006 + 0.016 * s)) + (tangent * math.cos(ang) + nin * math.sin(ang))
                       * (0.035 * s * g + 0.001 * i))
        tube(pts, lambda s: 0.0032 * (1 - 0.6 * s), segs=8, verts=verts, faces=faces, uvs=uvs, attrs=attrs)
    # UVs land at the lip's tip colour.
    return verts, faces, [(1.0, 0.5)] * len(verts), attrs


def frame_matrix(axis):
    """Rotation taking +Z to `axis`, with +Y (the dorsal sepal) as close to
    world up as it can be."""
    zz = axis.normalized()
    yy = (Z - zz * Z.dot(zz)).normalized()
    xx = yy.cross(zz)
    return Matrix((xx, yy, zz)).transposed()


def head_pose(t):
    k = stage(TURN, t)
    q0 = frame_matrix(BUD_AXIS).to_quaternion()
    q1 = frame_matrix(OPEN_AXIS).to_quaternion()
    q = q0.slerp(q1, k)
    swell = lerp(0.9, 1.0, stage(SWELL, t))
    return HEAD_BUD.lerp(HEAD_OPEN, k), q, swell


# ----------------------------------------------------------------------- main

def main():
    args = parse_args()
    os.makedirs(args.out, exist_ok=True)
    scene = reset_scene()
    setup_render(scene, args.res, args.samples, look="AgX - Punchy", exposure=-0.4)
    if args.border:
        x0, y0, x1, y1 = (float(x) for x in args.border.split(","))
        scene.render.use_border = scene.render.use_crop_to_border = True
        scene.render.border_min_x, scene.render.border_max_x = x0, x1
        scene.render.border_min_y, scene.render.border_max_y = 1 - y1, 1 - y0
    setup_world(scene)
    setup_camera(scene)
    centre = (HEAD_BUD + HEAD_OPEN) / 2
    # A soft key from the front upper left keeps the flower readable at any
    # temperature. The back and rim lights make the thin tepals glow and are
    # relit per output level (setup_compositor), so they follow CPU heat.
    add_area_light("Key", (-1.6, -2.2, 1.5), centre, 190, 1.1, (1.0, 0.97, 0.94), "ambient")
    add_area_light("Fill", (2.2, -2.0, -0.4), centre, 18, 2.5, (0.85, 0.90, 1.0), "ambient")
    add_area_light("Back", (1.0, 2.2, 1.2), centre, 1100, 1.2, (1.0, 0.90, 0.84), "key")
    add_area_light("Rim", (-1.4, 2.0, -0.5), centre, 350, 1.0, (1.0, 0.94, 0.90), "key")
    levels = {"dim": args.dim, "bright": args.bright}
    save = setup_compositor(scene, args.out, levels)

    mats = {
        "tepal": tepal_material(),
        "lip": lip_material(),
        "callus": callus_material(),
        "column": column_material(),
        "anther": anther_material(),
        "pedicel": stem_material("Pedicel", (0.20, 0.36, 0.045), (0.27, 0.42, 0.06), 0.34,
                                 node_colour=(0.24, 0.07, 0.05), scale=2.0, streak=0.03),
        "spike": stem_material("Spike", (0.075, 0.065, 0.030), (0.10, 0.07, 0.035), 0.55,
                               node_colour=(0.17, 0.035, 0.025), scale=3.0,
                               young_colour=(0.07, 0.14, 0.03), speckle=(0.20, 0.20, 0.12)),
    }

    head = bpy.data.objects.new("Head", None)
    bpy.context.collection.objects.link(head)
    head.rotation_mode = "QUATERNION"

    organs = []
    for spec in ORGANS:
        obj = new_object(spec["name"], head, mats["lip" if spec["name"] == "Lip" else "tepal"])
        sub = obj.modifiers.new("Subsurf", "SUBSURF")
        sub.levels = 1
        sub.render_levels = 1
        organs.append(obj)
    column = new_object("Column", head, mats["column"])
    anther = new_object("Anther", head, mats["anther"])
    cirri = new_object("Cirri", head, mats["lip"])
    callus = new_object("Callus", head, mats["callus"])
    pedicel = new_object("Pedicel", None, mats["pedicel"])
    spike = new_object("Spike", None, mats["spike"])
    replace_mesh(spike, *spike_geometry())

    # The spare bud: closed sepals on a short stalk from the second node,
    # further up the spike. It doesn't move.
    spare = bpy.data.objects.new("SpareBud", None)
    bpy.context.collection.objects.link(spare)
    spare_axis = Vector((0.45, -0.25, 0.86)).normalized()
    spare_base = NODE2 + Vector((0.16, -0.02, 0.10))
    spare.matrix_world = Matrix.Translation(spare_base) @ frame_matrix(spare_axis).to_4x4()
    for spec in ORGANS[:3]:
        obj = new_object("Spare" + spec["name"], spare, mats["tepal"])
        verts, faces, uvs, attrs, _ = organ_geometry(spec, 0.0, scale=0.55)
        replace_mesh(obj, verts, faces, uvs, attrs)
        obj.modifiers.new("Subsurf", "SUBSURF").levels = 1
    spare_stalk = new_object("SpareStalk", None, mats["pedicel"])
    v, f, uv, at = tube(bezier_path(NODE2, NODE2 + Vector((0.05, -0.01, 0.06)), spare_base - spare_axis * 0.05,
                                    spare_base, 30), lambda s: PEDICEL_R * 0.75, segs=16)
    finish_tube_mesh(spare_stalk, v, f, uv, at)

    if args.preview:
        values = [float(x) for x in args.preview.split(",")]
        names = [f"preview_{v:.2f}" for v in values]
    else:
        values = [i / (args.frames - 1) for i in range(args.start, args.frames)]
        names = [f"orchid_{i:03d}" for i in range(args.start, args.frames)]
        for level in levels:
            os.makedirs(os.path.join(args.out, level), exist_ok=True)

    for t, name in zip(values, names):
        loc, rot, swell = head_pose(t)
        head.location = loc
        head.rotation_quaternion = rot
        head.scale = (swell,) * 3
        bpy.context.view_layer.update()
        lip_at = None
        for obj, spec in zip(organs, ORGANS):
            verts, faces, uvs, attrs, at = organ_geometry(spec, t)
            replace_mesh(obj, verts, faces, uvs, attrs)
            if spec["name"] == "Lip":
                lip_at = at
        (cv, cf, cu), (av, af) = column_geometry(t)
        replace_mesh(column, cv, cf, cu)
        replace_mesh(anther, av, af)
        finish_tube_mesh(cirri, *cirri_geometry(lip_at(1.0), t))
        cv, cf, ca = callus_geometry(lip_at, t)
        replace_mesh(callus, cv, cf, None, ca)
        axis = (rot @ Z).normalized()
        finish_tube_mesh(pedicel, *pedicel_geometry(loc - axis * 0.01 * swell, axis))

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
