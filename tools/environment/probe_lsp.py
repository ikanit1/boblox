"""Verify real LSP initialize and changing diagnostics in an isolated scratch document."""
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]

def main():
    started = time.monotonic()
    target = ROOT/'docs/environment/lsp-validation.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps({'passed':False,'status':'RUNNING',
        'observedAt':datetime.now(timezone.utc).isoformat()})+'\n',encoding='utf-8')
    scratch = ROOT / 'build/environment-lsp'
    scratch.mkdir(parents=True, exist_ok=True)
    document = scratch / 'probe.luau'
    bad_text = '--!strict\nlocal count: number = "bad"\nreturn count\n'
    fixed_text = '--!strict\nlocal count: number = 1\nreturn count\n'
    document.write_text(bad_text, encoding='utf-8')
    uri = document.as_uri()
    server = Path(os.environ['LOCALAPPDATA']) / 'RobloxDev/bin/luau-lsp.exe'
    stderr_log = (scratch / 'server-stderr.log').open('wb')
    process = subprocess.Popen([str(server), 'lsp', '--stdio', '--no-flags-enabled'], cwd=scratch,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr_log)
    messages = queue.Queue()
    transcript = []
    def read():
        try:
            while True:
                headers = {}
                while True:
                    line = process.stdout.readline()
                    if not line:
                        return
                    if line in (b'\r\n', b'\n'):
                        break
                    key, value = line.decode().split(':', 1)
                    headers[key.lower()] = value.strip()
                size = int(headers['content-length'])
                payload = process.stdout.read(size)
                messages.put(json.loads(payload))
        except Exception as error:
            messages.put({'readerError': str(error)})
    threading.Thread(target=read, daemon=True).start()
    def send(value):
        transcript.append({'direction': 'send', 'message': value})
        payload = json.dumps(value).encode()
        process.stdin.write(f'Content-Length: {len(payload)}\r\n\r\n'.encode() + payload)
        process.stdin.flush()
    def wait(predicate, seconds=15):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                value = messages.get(timeout=max(.1, deadline-time.monotonic()))
            except queue.Empty:
                break
            transcript.append({'direction': 'receive', 'message': value})
            if 'readerError' in value:
                raise RuntimeError(value)
            if 'method' in value and 'id' in value:
                result = [{} for _ in value.get('params', {}).get('items', [])] if value['method']=='workspace/configuration' else None
                send({'jsonrpc':'2.0', 'id':value['id'], 'result': result})
            if predicate(value):
                return value
        raise TimeoutError('LSP response not received')
    try:
        send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{
            'processId':None,'rootUri':scratch.as_uri(),
            'workspaceFolders':[{'uri':scratch.as_uri(),'name':'RuleRoom LSP probe'}],
            'capabilities':{'workspace':{'configuration':False}, 'textDocument': {
                'diagnostic': {'dynamicRegistration': False, 'relatedDocumentSupport': False}}}}})
        initialized = wait(lambda v:v.get('id')==1)
        assert 'result' in initialized, initialized
        provider = initialized['result'].get('capabilities', {}).get('diagnosticProvider')
        assert provider, 'Server did not advertise pull diagnostics'
        send({'jsonrpc':'2.0','method':'initialized','params':{}})
        send({'jsonrpc':'2.0','method':'textDocument/didOpen','params':{'textDocument':{
            'uri':uri,'languageId':'luau','version':1,'text':bad_text}}})
        send({'jsonrpc':'2.0','id':2,'method':'textDocument/diagnostic','params':{
            'textDocument':{'uri':uri},'identifier':provider.get('identifier', 'luau')}})
        bad = wait(lambda v:v.get('id')==2)
        assert bad.get('result', {}).get('kind') == 'full', bad
        bad_diagnostics = bad['result']['items']
        assert any(d.get('severity')==1 and 'number' in d['message'] and 'string' in d['message'] for d in bad_diagnostics), bad
        send({'jsonrpc':'2.0','method':'textDocument/didChange','params':{
            'textDocument':{'uri':uri,'version':2},'contentChanges':[{'text':fixed_text}]}})
        send({'jsonrpc':'2.0','id':3,'method':'textDocument/diagnostic','params':{
            'textDocument':{'uri':uri},'identifier':provider.get('identifier', 'luau')}})
        clean = wait(lambda v:v.get('id')==3)
        assert clean.get('result', {}).get('kind') == 'full', clean
        clean_diagnostics = clean['result']['items']
        assert not clean_diagnostics, clean
        # Disk still contains the bad version: this proves didChange affected the live document.
        assert document.read_text(encoding='utf-8') == bad_text
        document.write_text(fixed_text, encoding='utf-8')
        report = {'passed':True,'status':'PASS','observedAt':datetime.now(timezone.utc).isoformat(),
                  'scope':'Real LSP initialize, document open/change and pull diagnostics on isolated pure Luau; not VS Code UI, Roblox definitions/sourcemap, or whole-game type acceptance',
                  'serverInfo':initialized['result'].get('serverInfo'),
                  'method':'textDocument/diagnostic','diagnosticProvider':provider,
                  'unsavedDidChangeVerified':True,
                  'typeMismatchDiagnostics':bad_diagnostics,'correctedDiagnostics':clean_diagnostics}
        send({'jsonrpc':'2.0','method':'textDocument/didClose','params':{'textDocument':{'uri':uri}}})
        send({'jsonrpc':'2.0','id':4,'method':'shutdown','params':None})
        shutdown = wait(lambda v:v.get('id')==4,5)
        assert 'result' in shutdown and 'error' not in shutdown, shutdown
        send({'jsonrpc':'2.0','method':'exit','params':None})
        report['exitCode'] = process.wait(timeout=5)
        assert report['exitCode'] == 0, report
        report['elapsedSeconds'] = time.monotonic() - started
        target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(report))
    except Exception as error:
        target.write_text(json.dumps({'passed':False,'status':'FAIL',
            'observedAt':datetime.now(timezone.utc).isoformat(),'failure':str(error),
            'scope':'Isolated pure Luau LSP protocol probe'},indent=2)+'\n',encoding='utf-8')
        raise
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        stderr_log.close()
        (scratch/'protocol.json').write_text(json.dumps(transcript,indent=2)+'\n',encoding='utf-8')

if __name__ == '__main__':
    main()
