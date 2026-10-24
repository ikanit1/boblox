"""Run with the installed MCP venv Python. Performs real read-only integration checks."""
import argparse
import asyncio
import json
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


def checked(reply):
    assert not reply.isError, reply
    body = reply.structuredContent
    if body is None:
        body = json.loads(next(item.text for item in reply.content if item.type == 'text'))
    assert body.get('status') == 'ok', body
    return body


async def run(deployment):
    server = StdioServerParameters(command=deployment['command'], args=deployment['args'])
    async with stdio_client(server) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            initialize = await session.initialize()
            tools = await session.list_tools()
            names = [tool.name for tool in tools.tools]
            assert {'get_objects_summary', 'execute_blender_code'} <= set(names), names
            summary = checked(await session.call_tool('get_objects_summary', {}))
            query = checked(await session.call_tool('execute_blender_code', {'code':
                "import bpy\nresult={'version':bpy.app.version_string,'file':bpy.data.filepath,"
                "'background':bpy.app.background,'objects':len(bpy.data.objects),"
                "'bridgeOwner':bpy.app.driver_namespace.get('ruleroom_mcp_bridge')}"}))
            assert query['result']['bridgeOwner'] == 'official-v1', query
            return {'passed': True, 'scope': 'MCP handshake, tools and read-only Blender scene query',
                    'serverInfo': initialize.serverInfo.model_dump(mode='json'),
                    'toolCount': len(names), 'tools': names,
                    'objectsSummaryStatus': summary['status'], 'query': query['result']}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-home', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    deployment = json.loads((args.runtime_home / 'deployment.json').read_text(encoding='utf-8-sig'))
    result = asyncio.run(asyncio.wait_for(run(deployment), timeout=60))
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding='utf-8')
    print(encoded)
