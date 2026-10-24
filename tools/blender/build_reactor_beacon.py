"""Original low-poly RuleRoom prop. Run inside a fresh Blender MCP scratch scene.

The asset is deliberately not mapped into the game. Roblox import is a separate gate.
One Blender metre is specified as 1 / 0.28 Roblox studs in this asset's manifest.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector


def build(output: Path):
    output.mkdir(parents=True, exist_ok=True)
    assert not bpy.data.scenes.get('RuleRoom-AssetLab'), 'Use a fresh scratch bridge before rebuilding'
    assert not (output / 'reactor_beacon.blend').exists(), 'Refusing to replace an existing source asset'
    scene = bpy.data.scenes.new('RuleRoom-AssetLab')
    bpy.context.window.scene = scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    scene['asset_id'] = 'ruleroom-reactor-beacon-v1'
    scene['purpose'] = 'Decorative prototype; no gameplay or collision authority'
    collection = bpy.data.collections.new('ASSET-ReactorBeacon')
    scene.collection.children.link(collection)
    stage = bpy.data.collections.new('STAGE-PreviewOnly')
    scene.collection.children.link(stage)

    def linear(value):
        value /= 255
        return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4

    def material(name, rgb, metal=0.0, roughness=.45, emission=0.0):
        mat = bpy.data.materials.new('MAT-' + name)
        mat.use_nodes = True
        rgba = (*[linear(v) for v in rgb], 1)
        mat.diffuse_color = rgba
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = rgba
        shader.inputs['Metallic'].default_value = metal
        shader.inputs['Roughness'].default_value = roughness
        if emission:
            shader.inputs['Emission Color'].default_value = rgba
            shader.inputs['Emission Strength'].default_value = emission
        return mat

    navy = material('NavyPaint', (18, 30, 50), roughness=.38)
    steel = material('BrushedSteel', (165, 185, 205), metal=1, roughness=.4)
    cyan = material('ReactorCyan', (80, 225, 255), roughness=.28, emission=1.2)
    amber = material('WarningAmber', (255, 213, 79), roughness=.4)
    dark = material('PreviewFloor', (12, 20, 34), roughness=.8)
    parts = []

    def finish(obj, name, mat, target=collection):
        obj.name = 'GEO-' + name
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        target.objects.link(obj)
        obj.data.materials.append(mat)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        if target == collection:
            parts.append(obj)
        return obj

    def cylinder(name, radius, depth, z, mat, vertices=16):
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth,
                                           location=(0, 0, z), calc_uvs=True)
        return finish(bpy.context.object, name, mat)

    def box(name, dimensions, position, mat, angle=0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=position)
        obj = bpy.context.object
        obj.dimensions = dimensions
        obj.rotation_euler.z = angle
        finish(obj, name, mat)
        bevel = obj.modifiers.new('MobileBevel', 'BEVEL')
        bevel.width = .008
        bevel.segments = 1
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        return obj

    cylinder('Foot', .56, .14, .07, navy, 12)
    cylinder('FootTrim', .49, .035, .1575, steel, 12)
    cylinder('LowerHousing', .35, .19, .27, navy, 12)
    cylinder('LowerLight', .355, .045, .385, cyan, 16)
    cylinder('Core', .18, .90, .88, cyan, 16)
    cylinder('TopHousing', .35, .18, 1.42, navy, 12)
    cylinder('UpperLight', .355, .045, 1.315, cyan, 16)
    cylinder('Cap', .46, .17, 1.595, navy, 12)
    cylinder('CapTrim', .38, .035, 1.485, steel, 12)
    for i in range(4):
        angle = math.pi / 4 + i * math.pi / 2
        x, y = .28 * math.cos(angle), .28 * math.sin(angle)
        box('CagePost%02d' % (i + 1), (.075, .075, .98), (x, y, .88), steel, angle)
    for i in range(3):
        bpy.ops.mesh.primitive_torus_add(major_segments=24, minor_segments=6,
                                        major_radius=.225, minor_radius=.022,
                                        location=(0, 0, .57 + i * .30))
        finish(bpy.context.object, 'CoreRing%02d' % (i + 1), steel)
    for i in range(3):
        box('ChargeIndicator%02d' % (i + 1), (.075, .018, .035),
            ((i - 1) * .11, -.349, .275), amber)
    for obj in parts:
        # Each separate closed component has UVs; no baked texture is claimed.
        assert obj.data.uv_layers, obj.name + ': missing UVs'
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        assert all(edge.is_manifold for edge in bm.edges), obj.name + ': open mesh'
        assert all(math.isfinite(c) for v in bm.verts for c in v.co), obj.name
        bm.free()
        obj.data.calc_loop_triangles()
    triangles = sum(len(obj.data.loop_triangles) for obj in parts)
    assert triangles <= 3000, triangles
    points = [obj.matrix_world @ Vector(corner) for obj in parts for corner in obj.bound_box]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    dimensions = [high[i] - low[i] for i in range(3)]
    assert abs(dimensions[2] - 1.68) < .001, dimensions

    bpy.ops.mesh.primitive_plane_add(size=20)
    finish(bpy.context.object, 'PreviewFloor', dark, stage)
    world = bpy.data.worlds.new('WORLD-AssetLab')
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.04, .055, .08, 1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = .6
    target = Vector((0, 0, .85))

    def aim(obj):
        obj.rotation_euler = (target - obj.location).to_track_quat('-Z', 'Y').to_euler()

    for name, location, energy, size, color in [
        ('Key', (3, -4, 4), 500, 3, (1, .92, .84)),
        ('Fill', (-3, -1, 2.5), 250, 3, (.52, .74, 1)),
        ('Rim', (2, 3, 3), 700, 2, (.52, .88, 1)),
    ]:
        data = bpy.data.lights.new('LGT-' + name, 'AREA')
        data.energy, data.shape, data.size, data.color = energy, 'DISK', size, color
        obj = bpy.data.objects.new('LGT-' + name, data)
        stage.objects.link(obj)
        obj.location = location
        aim(obj)
    camera = bpy.data.objects.new('CAM-ReactorHero', bpy.data.cameras.new('CAM-ReactorHero'))
    stage.objects.link(camera)
    camera.location = (2.9, -4.2, 2.65)
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 2.5
    aim(camera)
    scene.camera = camera
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 640, 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'AgX'
    scene.render.filepath = str(output / 'reactor_beacon-preview.png')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.export_scene.gltf(filepath=str(output / 'reactor_beacon.glb'),
                              export_format='GLB', use_selection=True, use_active_scene=True, export_apply=True,
                              export_animations=False, export_yup=True)
    bpy.ops.export_scene.fbx(filepath=str(output / 'reactor_beacon.fbx'),
                             use_selection=True, object_types={'MESH'},
                             apply_unit_scale=True, apply_scale_options='FBX_SCALE_ALL',
                             use_mesh_modifiers=True, bake_anim=False, axis_forward='-Z', axis_up='Y')
    bpy.ops.wm.save_as_mainfile(filepath=str(output / 'reactor_beacon.blend'))
    bpy.ops.render.render(write_still=True)
    manifest = {
        'assetId': 'ruleroom-reactor-beacon-v1', 'status': 'Blender pipeline proof; NOT imported or shipped',
        'source': 'Original geometry generated by tools/blender/build_reactor_beacon.py',
        'license': 'Project-authored; no third-party meshes/textures/fonts',
        'blender': bpy.app.version_string, 'backend': 'Official Blender Lab MCP 1.0.2',
        'exportScope': 'Active asset-lab scene and selected 19 meshes only; original default Scene excluded',
        'meshObjects': len(parts), 'triangles': triangles, 'triangleBudget': 3000,
        'materials': 4, 'dimensionsMetres': dimensions,
        'nominalRobloxDimensionsStuds': [v / .28 for v in dimensions],
        'pivot': 'Each component retains placement; assembled base centre at world origin, floor Z=0',
        'uvs': 'Primitive UVs present on all components; no baked texture or UV packing claim',
        'collision': 'Decorative candidate: no gameplay collision proxy exported; choose CanCollide=false on import',
        'limits': ['Roblox importer orientation/scale/materials not validated',
                   'Emission should be rebuilt as Roblox Neon/lighting after import',
                   'No physical-mobile benchmark or production visual acceptance'],
        'files': {},
    }
    for path in sorted(output.iterdir()):
        if path.is_file() and path.suffix.lower() in {'.blend', '.glb', '.fbx', '.png'}:
            manifest['files'][path.name] = {'bytes': path.stat().st_size,
                                          'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    print(json.dumps(build(args.output.resolve()), ensure_ascii=True))
