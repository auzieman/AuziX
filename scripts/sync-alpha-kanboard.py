#!/usr/bin/env python3
"""Sync the recorded AX issues via Kanboard API. Defaults to preview only."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
ledger = Path(__file__).resolve().parents[1] / 'notes/alpha-release-issues-2026-09-05.md'
text = ledger.read_text()
issues = []
for match in re.finditer(r'^## (AX-\d{3}) — ([^\n]+)\n(.*?)(?=^## |\Z)', text, re.M | re.S):
    key, title, body = match.groups()
    issues.append({'reference': 'auzix-alpha-20260905:' + key,
                   'title': key + ' — ' + title,
                   'description': body.strip() + '\n\nSource: AuziX/' + str(ledger.relative_to(ledger.parents[1]))})
assert len(issues) == 12
if not args.apply:
    print(json.dumps(issues, indent=2))
    raise SystemExit()

# Credentials stay on VM138. SQLite is read-only for credential retrieval;
# every mutation and readback uses the application's JSON-RPC API.
remote = r'''
import base64,json,sqlite3,sys,urllib.request
items=json.loads(sys.argv[1])
db=sqlite3.connect('file:/var/www/html/kanboard/data/db.sqlite?mode=ro',uri=True)
row=db.execute('select value from settings where option=?',('api_token',)).fetchone()
if not row or not row[0]: raise SystemExit('Kanboard API token not found; no changes')
auth=base64.b64encode(('jsonrpc:'+row[0]).encode()).decode()
def rpc(method,params):
    req=urllib.request.Request('http://127.0.0.1/kanboard/jsonrpc.php',
        data=json.dumps(dict(jsonrpc='2.0',id=1,method=method,params=params)).encode(),
        headers={'Content-Type':'application/json','Authorization':'Basic '+auth})
    with urllib.request.urlopen(req,timeout=20) as response: result=json.load(response)
    if 'error' in result: raise RuntimeError(str(result['error']))
    return result['result']
project=rpc('getProjectById',{'project_id':3})
assert project['name']=='AUZiX Package Factory'
tasks=rpc('getAllTasks',{'project_id':3,'status_id':1})
for item in items:
    marker='<!-- ai_worker_ref:'+item['reference']+' -->'
    matches=[t for t in tasks if marker in (t.get('description') or '')]
    assert len(matches)<=1
    description=item['description']+'\n\n'+marker
    if matches:
        tid=int(matches[0]['id'])
        assert rpc('updateTask',{'id':tid,'title':item['title'],'description':description})
    else:
        tid=rpc('createTask',{'project_id':3,'column_id':21,'title':item['title'],'description':description})
        assert tid
    check=rpc('getTask',{'task_id':int(tid)})
    assert marker in check['description']
    print(json.dumps({'reference':item['reference'],'task_id':tid,'status':'verified'}),flush=True)
'''
import shlex
import base64
encoded = base64.b64encode(remote.encode()).decode()
bootstrap = "import base64;exec(base64.b64decode(" + repr(encoded) + "))"
command = 'qm guest exec 138 -- python3 -c ' + shlex.quote(bootstrap) + ' ' + shlex.quote(json.dumps(issues))
result = subprocess.run(['ssh', 'root@192.168.1.9', command], check=True,
                        capture_output=True, text=True)
guest = json.loads(result.stdout)
if not guest.get('exited') or guest.get('exitcode') != 0:
    raise SystemExit('Guest sync failed: ' + guest.get('err-data', 'no result'))
receipts = [json.loads(line) for line in guest.get('out-data', '').splitlines() if line]
assert len(receipts) == 12, 'Missing API readback receipts; do not claim sync success'
assert {r['reference'] for r in receipts} == {i['reference'] for i in issues}
print(json.dumps(receipts, indent=2))
