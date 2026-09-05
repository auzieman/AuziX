#!/usr/bin/env python3
"""Sync the recorded AX issues via Kanboard API. Defaults to preview only."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true')
parser.add_argument('--comment-file', type=Path, help='Post a dated Markdown update; never rewrite description')
parser.add_argument('--issue', choices=['AX-%03d' % n for n in range(1, 13)])
parser.add_argument('--order-columns', action='store_true', help='Only reorder project3 columns; preserve cards')
parser.add_argument('--start-ax001', action='store_true', help='Pick up task54 in the top active lane')
parser.add_argument('--validate-ax001', action='store_true', help='Move fixed task54 to validation; not Done')
parser.add_argument('--plan-ax001', action='store_true', help='Return failed task54 validation to Planning')
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
if bool(args.comment_file) != bool(args.issue):
    parser.error('--comment-file and --issue must be supplied together')
if args.comment_file:
    import hashlib
    body = args.comment_file.read_text().strip()
    if not body:
        parser.error('comment file is empty')
    issues = [item for item in issues if item['reference'].endswith(':' + args.issue)]
    issues[0]['comment'] = body
    issues[0]['comment_marker'] = '<!-- auzix-update:' + hashlib.sha256(body.encode()).hexdigest() + ' -->'
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
if sys.argv[2] in ('start-ax001','validate-ax001','plan-ax001'):
    task=rpc('getTask',{'task_id':54})
    assert 'ai_worker_ref:auzix-alpha-20260905:AX-001' in task['description']
    column={'validate-ax001':35, 'start-ax001':11, 'plan-ax001':21}[sys.argv[2]]
    assert rpc('moveTaskPosition',{'project_id':3,'task_id':54,'column_id':column,'position':1,'swimlane_id':3})
    task=rpc('getTask',{'task_id':54})
    assert int(task['column_id'])==column and int(task['swimlane_id'])==3
    print(json.dumps({'status':'verified','task_id':54,'column_id':column,'swimlane':'Default / active now'}))
    raise SystemExit()
if sys.argv[2]=='order':
    desired=[9,21,10,25,30,11,32,38,41,35,43,12]
    before=rpc('getColumns',{'project_id':3})
    assert {int(c['id']) for c in before}==set(desired)
    def assignments():
        return sorted((int(t['id']),int(t['column_id'])) for status in (0,1)
            for t in rpc('getAllTasks',{'project_id':3,'status_id':status}))
    cards=assignments()
    for position,cid in enumerate(desired,1):
        assert rpc('changeColumnPosition',{'project_id':3,'column_id':cid,'position':position})
    after=rpc('getColumns',{'project_id':3})
    assert [int(c['id']) for c in sorted(after,key=lambda c:int(c['position']))]==desired
    assert assignments()==cards
    assert {(c['id'],c['title']) for c in before}=={(c['id'],c['title']) for c in after}
    print(json.dumps({'status':'verified','columns':[(c['id'],c['title'],c['position']) for c in after], 'task_assignments':'unchanged'}))
    raise SystemExit()
tasks=rpc('getAllTasks',{'project_id':3,'status_id':1})
for item in items:
    marker='<!-- ai_worker_ref:'+item['reference']+' -->'
    matches=[t for t in tasks if marker in (t.get('description') or '')]
    assert len(matches)<=1
    description=item['description']+'\n\n'+marker
    if matches:
        tid=int(matches[0]['id'])
        # Existing task scope and human edits are authoritative.
    else:
        tid=rpc('createTask',{'project_id':3,'column_id':21,'title':item['title'],'description':description})
        assert tid
    check=rpc('getTask',{'task_id':int(tid)})
    assert marker in check['description']
    if matches:
        assert check['description']==matches[0]['description']
        assert check['title']==matches[0]['title']
    if 'comment' in item:
        comments=rpc('getAllComments',{'task_id':int(tid)})
        update_marker=item['comment_marker']
        if not any(update_marker in c['comment'] for c in comments):
            author=rpc('getUserByName',{'username':'admin'})
            assert author and author['id']
            assert rpc('createComment',{'task_id':int(tid),'user_id':int(author['id']),
                'content':item['comment']+'\n\n'+update_marker})
        comments=rpc('getAllComments',{'task_id':int(tid)})
        assert sum(update_marker in c['comment'] for c in comments)==1
    print(json.dumps({'reference':item['reference'],'task_id':tid,'status':'verified'}),flush=True)
'''
import shlex
import base64
encoded = base64.b64encode(remote.encode()).decode()
bootstrap = "import base64;exec(base64.b64decode(" + repr(encoded) + "))"
mode = 'plan-ax001' if args.plan_ax001 else ('validate-ax001' if args.validate_ax001 else ('start-ax001' if args.start_ax001 else ('order' if args.order_columns else 'sync')))
command = 'qm guest exec 138 -- python3 -c ' + shlex.quote(bootstrap) + ' ' + shlex.quote(json.dumps(issues)) + ' ' + mode
result = subprocess.run(['ssh', 'root@192.168.1.9', command], check=True,
                        capture_output=True, text=True)
guest = json.loads(result.stdout)
if not guest.get('exited') or guest.get('exitcode') != 0:
    raise SystemExit('Guest sync failed: ' + guest.get('err-data', 'no result').splitlines()[-1])
receipts = [json.loads(line) for line in guest.get('out-data', '').splitlines() if line]
if args.order_columns or args.start_ax001 or args.validate_ax001 or args.plan_ax001:
    assert len(receipts)==1 and receipts[0]['status']=='verified'
else:
    assert len(receipts) == len(issues), 'Missing API readback receipts; do not claim sync success'
    assert {r['reference'] for r in receipts} == {i['reference'] for i in issues}
print(json.dumps(receipts, indent=2))
