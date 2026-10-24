"""Install pinned Windows tools from the environment lock, preserving existing differing files."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-only',action='store_true')
    args=parser.parse_args()
    base=Path(os.environ['LOCALAPPDATA'])/'RobloxDev'
    cache=base/'downloads';cache.mkdir(parents=True,exist_ok=True)
    lock=json.loads((ROOT/'docs/environment/tooling-lock.json').read_text())
    allowed={'rojo-rbx/rokit':'rokit.exe','UpliftGames/wally':'wally.exe','JohnnyMorganz/luau-lsp':'luau-lsp.exe'}
    installed=[]
    for item in lock['assets']:
        url=item['url']; parsed=urllib.parse.urlsplit(url)
        assert parsed.scheme=='https' and not parsed.query
        if item['tool'] in {'Node.js','Visual Studio Code'}:
            if item['tool']=='Node.js':
                assert parsed.hostname=='nodejs.org' and parsed.path.startswith('/dist/'+item['version']+'/')
                destination=base/'node'/item['version']
                executable=destination/('node-'+item['version']+'-win-x64')/'node.exe'
            else:
                assert parsed.hostname=='vscode.download.prss.microsoft.com'
                destination=base/'vscode'/item['version'];executable=destination/'Code.exe'
        else:
            repository=item['repository'];assert repository in allowed
            assert url.startswith('https://github.com/'+repository+'/releases/download/'+item['tag']+'/')
            destination=base/'bin';executable=destination/allowed[repository]
        expected=item['sha256'];assert len(expected)==64 and all(c in '0123456789abcdef' for c in expected)
        archive=cache/('environment-'+parsed.path.rsplit('/',1)[-1])
        if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=expected:
            if args.verify_only:
                assert executable.is_file(),'Missing tool: '+str(executable)
                installed.append({'tool':item['tool'],'path':str(executable),'check':'present; archive not cached under bootstrap name'})
                continue
            request=urllib.request.Request(url,headers={'User-Agent':'RuleRoomEnvironment/1.0'})
            with urllib.request.urlopen(request,timeout=60) as response:payload=response.read()
            assert hashlib.sha256(payload).hexdigest()==expected,'Download checksum mismatch'
            archive.write_bytes(payload)
        with zipfile.ZipFile(archive) as bundle:
            entries=bundle.infolist()
            if item['tool'] not in {'Node.js','Visual Studio Code'}:
                entries=[e for e in entries if PurePosixPath(e.filename).name==allowed[item['repository']]]
                assert len(entries)==1
            for entry in entries:
                rel=PurePosixPath(entry.filename)
                assert not rel.is_absolute() and '..' not in rel.parts and ':' not in entry.filename
                if entry.is_dir():continue
                target=destination.joinpath(*rel.parts) if item['tool'] in {'Node.js','Visual Studio Code'} else executable
                payload=bundle.read(entry)
                if target.exists():assert target.read_bytes()==payload,'Preserve differing existing file: '+str(target)
                elif args.verify_only:raise RuntimeError('Missing installed file: '+str(target))
                else:
                    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(payload)
        assert executable.is_file()
        if item['tool']=='Visual Studio Code':(destination/'data').mkdir(exist_ok=True)
        installed.append({'tool':item['tool'],'path':str(executable),'check':'pinned archive and selected installed files match'})
    print(json.dumps({'passed':True,'tools':installed,'scope':'Windows file integrity/install only; app startup and integration are separate checks'}))

if __name__=='__main__':main()
