"""Persistent Codex entrypoint for official Blender MCP with an isolated local bridge.

Only a background process launched by this wrapper is terminated on normal MCP exit.
An existing bridge must carry our in-memory marker before it can be reused.
"""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time


def query_bridge(port):
    request = {'type': 'execute', 'strict_json': True,
               'code': "import bpy\nresult={'owner':bpy.app.driver_namespace.get('ruleroom_mcp_bridge'),'version':bpy.app.version_string,'file':bpy.data.filepath}"}
    with socket.create_connection(('127.0.0.1', port), timeout=1) as sock:
        sock.settimeout(3)
        sock.sendall(json.dumps(request).encode() + b'\0')
        data = bytearray()
        while b'\0' not in data:
            chunk = sock.recv(65536)
            if not chunk:
                raise RuntimeError('Blender bridge closed before its response')
            data.extend(chunk)
            if len(data) > 1024 * 1024:
                raise RuntimeError('Unexpected bridge response size')
    response = json.loads(data.partition(b'\0')[0])
    if response.get('status') != 'ok' or response.get('result', {}).get('owner') != 'official-v1':
        raise RuntimeError('Port is occupied by an unrecognised Blender instance; choose another port')
    return response['result']


def port_is_free(port):
    # A closed Windows loopback port may time out rather than refuse a connect.
    # Probe binding first; never launch a second backend over an existing listener.
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--blender', required=True, type=Path)
    parser.add_argument('--runtime-home', required=True, type=Path)
    parser.add_argument('--port', type=int, default=9877)
    args = parser.parse_args()
    assert args.blender.is_file(), args.blender
    assert 1024 <= args.port <= 65535
    source = args.runtime_home / 'source-dbbf836ad4b1' / 'addon'
    assert (source / 'blender_mcp_addon' / '__init__.py').is_file(), source
    owned = None
    log = None
    try:
        if not port_is_free(args.port):
            query_bridge(args.port)
        else:
            log = (args.runtime_home / 'bridge.log').open('ab')
            command = [str(args.blender), '--online-mode', '--background', '--factory-startup',
                       '--python', str(Path(__file__).with_name('start_bridge.py')), '--',
                       '--addon-root', str(source), '--port', str(args.port)]
            owned = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                     creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            deadline = time.monotonic() + 40
            while True:
                if owned.poll() is not None:
                    raise RuntimeError('Blender failed to start; read the local bridge.log')
                try:
                    query_bridge(args.port)
                    break
                except (ConnectionRefusedError, TimeoutError, socket.timeout):
                    if time.monotonic() >= deadline:
                        raise RuntimeError('Blender bridge startup timed out')
                    time.sleep(.25)
        environment = os.environ.copy()
        environment.update(BLENDER_MCP_HOST='127.0.0.1', BLENDER_MCP_PORT=str(args.port),
                           BLENDER_PATH=str(args.blender))
        return subprocess.call([sys.executable, '-m', 'blmcp'], env=environment)
    finally:
        if owned is not None and owned.poll() is None:
            owned.terminate()
            try:
                owned.wait(timeout=8)
            except subprocess.TimeoutExpired:
                owned.kill()
                owned.wait(timeout=3)
        if log:
            log.close()


if __name__ == '__main__':
    raise SystemExit(main())
