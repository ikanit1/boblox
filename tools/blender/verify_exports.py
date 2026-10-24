"""Blender CLI round-trip inspection of our FBX/GLB, with no file changes."""
import argparse
import json
from pathlib import Path
import sys
import bpy
from mathutils import Vector

parser=argparse.ArgumentParser()
parser.add_argument('--asset',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
results=[]
for suffix in ['.fbx','.glb']:
    scene=bpy.data.scenes.new('Verify'+suffix)
    bpy.context.window.scene=scene
    path=args.asset.with_suffix(suffix)
    if suffix=='.fbx':
        bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[obj for obj in scene.objects if obj.type=='MESH']
    bpy.context.view_layer.update()
    points=[obj.matrix_world @ v.co for obj in meshes for v in obj.data.vertices]
    sizes=[max(p[i] for p in points)-min(p[i] for p in points) for i in range(3)]
    triangles=0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles+=len(obj.data.loop_triangles)
        assert obj.data.uv_layers,obj.name
    assert len(meshes)==19,(suffix,len(meshes))
    assert triangles==1616,(suffix,triangles)
    assert all(abs(a-b)<.001 for a,b in zip(sizes,[1.12,1.12,1.68])),(suffix,sizes)
    results.append({'format':suffix,'meshes':len(meshes),'triangles':triangles,
                    'dimensionsMetres':sizes,'uvPresent':True,'passed':True})
args.out.write_text(json.dumps({'blender':bpy.app.version_string,'results':results,
                              'scope':'Blender importer round-trip only; not Roblox importer'},indent=2)+'\n',encoding='utf-8')
print('EXPORT_ROUNDTRIP_PASS '+json.dumps(results))
