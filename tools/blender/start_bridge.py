"""Load the official add-on for this process only, without saving user preferences."""
import argparse
from pathlib import Path
import sys

import addon_utils
import bpy

parser = argparse.ArgumentParser()
parser.add_argument('--addon-root', required=True, type=Path)
parser.add_argument('--host', default='127.0.0.1', choices=['127.0.0.1'])
parser.add_argument('--port', default=9877, type=int)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert 1024 <= args.port <= 65535
addon = args.addon_root.resolve() / 'blender_mcp_addon'
assert (addon / '__init__.py').is_file(), addon
sys.path.insert(0, str(addon.parent))
addon_utils.modules_refresh()
addon_utils.enable('blender_mcp_addon', default_set=True, persistent=True)
import blender_mcp_addon
preferences = bpy.context.preferences.addons['blender_mcp_addon'].preferences
preferences.host = args.host
preferences.port = args.port
preferences.use_autostart = False
bpy.app.driver_namespace['ruleroom_mcp_bridge'] = 'official-v1'
if bpy.app.background:
    from blender_mcp_addon.cli import cli_execute
    raise SystemExit(cli_execute(['--host', args.host, '--port', str(args.port)]))
else:
    assert bpy.ops.blmcp.server_start() == {'FINISHED'}
    print('RuleRoom official MCP bridge listening on %s:%s' % (args.host, args.port))
