#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Render complete native comparison records as a self-contained interactive chart."""
from pathlib import Path
import argparse, hashlib, json, re, statistics
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('records',nargs='+',type=Path)
parser.add_argument('--samples-per-pass',type=int,default=7)
parser.add_argument('--output',type=Path,default=Path('.build/report-staging'))
args=parser.parse_args()
if args.samples_per_pass<1:parser.error('--samples-per-pass must be positive')
files=args.records
resolved=[p.resolve(strict=True) for p in files]
contents=[p.read_bytes() for p in resolved]
if len(set(resolved))!=len(files) or len({hashlib.sha256(data).hexdigest() for data in contents})!=len(files):
 raise ValueError('duplicate input record')
records=[json.loads(data) for data in contents]
if len({r['journal_sha256'] for r in records})!=len(records):
 raise ValueError('duplicate measurement journal')
if not records or not all(r['phase']=='compare' and not r['inputs']['source']['status'] for r in records):
 raise ValueError('complete clean-source comparison records required')
first=records[0]
engines=('A','B','rust-csv','csv-core','simd-csv','libcsv')
cases={(name,op,chunk) for name in first['fixtures'] for op in ('parse','write')
       for chunk in ((1,64,4096,65536) if name=='simple' and op=='parse' else (4096,))}
expected={(fixture,op,chunk,engine,sample) for fixture,op,chunk in cases
          for engine in engines for sample in range(args.samples_per_pass)}
groups={}
for r in records:
 if any(r[key]!=first[key] for key in ('inputs','harness','fixtures','flags','build_affinity','build_record_sha256','controls_sha256')):
  raise ValueError('source, tools, dependencies, controls or build configuration differ across passes')
 if r['host']['affinity']!=first['host']['affinity'] or r['host']['platform']!=first['host']['platform']:
  raise ValueError('runtime affinity/platform differ')
 for variant in ('A','B'):
  if r['builds'][variant]['generated_c_sha256']!=first['builds'][variant]['generated_c_sha256'] or r['builds'][variant]['binary']['sections']!=first['builds'][variant]['binary']['sections']:
   raise ValueError('Goose generated C or executable sections differ')
 for engine in engines[2:]:
  if r['binaries'][engine]!=first['binaries'][engine]:raise ValueError('alternative executable differs: '+engine)
 if [x['ordinal'] for x in r['samples']]!=list(range(len(r['samples']))):raise ValueError('invalid sample ordinals')
 seen=set()
 for x in r['samples']:
  key=(x['fixture'],x['operation'],x['chunk'],x['engine'],x['sample'])
  if key in seen or key not in expected:raise ValueError('duplicate or unexpected sample cell')
  seen.add(key)
  if not 0<x['elapsed_ns']<2**63 or not 0<x['counts'][1]<2**63:raise ValueError('invalid timing or byte count')
  if x['counts'][1]!=r['fixtures'][x['fixture']]['wire']['bytes']*x['repeats']:raise ValueError('wire byte accounting differs')
  groups.setdefault(key[:4],[]).append(x['elapsed_ns']/x['counts'][1])
 if seen!=expected:raise ValueError('incomplete case/engine/sample matrix')
rows=[dict(fixture=k[0],operation=k[1],chunk=k[2],engine=k[3],n=len(v),median=1000/statistics.median(v),low=1000/max(v),high=1000/min(v)) for k,v in groups.items()]
head=first['inputs']['source']['head']
if not re.fullmatch(r'[0-9a-f]{40}',head):raise ValueError('invalid implementation commit')
data=json.dumps(rows).replace('<',r'\u003c').replace('&',r'\u0026')
html='''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
body{margin:0;font:14px var(--font-sans,system-ui);color:var(--foreground)}
.controls{display:flex;flex-wrap:wrap;gap:12px;margin:0 0 16px}label{display:grid;gap:5px;font-size:12px;color:var(--muted-foreground,var(--foreground))}select{font:inherit;font-size:14px;border:1px solid var(--border);border-radius:var(--radius);padding:7px 9px;background:var(--card);color:var(--foreground)}
p{line-height:1.5}small,.note{font-size:12px;color:var(--muted-foreground,var(--foreground))}svg{width:100%;height:325px;display:block}.table{overflow:auto}table{border-collapse:collapse;font-size:12px;width:100%}th,td{padding:8px;text-align:left;border-bottom:1px solid var(--border);white-space:nowrap}summary{cursor:pointer;margin:14px 0}a{color:var(--primary)}
</style></head><body><div class="controls"><label>Workload<select id="fixture"></select></label><label>Operation<select id="operation"><option value="parse">Reader</option><option value="write">Writer</option></select></label><label>Input chunk<select id="chunk"></select></label></div><svg id="plot" role="img" aria-label="Median CSV throughput with sample ranges"></svg><p id="caption" class="note"></p><p class="note">Valid-data owned-row / complete-row-output tier. Whiskers show the full sample range. Shared host; CPU affinity provides no isolation. Goose retains strict grammar and budgets; external engines retain their native contracts.</p><details><summary>Contract differences</summary><div class="table"><table><thead><tr><th>Native API property</th><th>Goose CSV</th><th>Rust csv / core</th><th>simd-csv</th><th>libcsv</th></tr></thead><tbody><tr><td>Strict malformed quoting</td><td>Yes</td><td>Permissive</td><td>Permissive</td><td>Strict + strict-fini</td></tr><tr><td>Zero-field blank records</td><td>Preserved</td><td>Skipped</td><td>Skipped</td><td>Skipped by default</td></tr><tr><td>Initial BOM bytes preserved</td><td>Yes</td><td>Native differences</td><td>Chunk-dependent trimming</td><td>Yes</td></tr><tr><td>Four exact budgets / error positions</td><td>Built in</td><td>Different / absent</td><td>Different / absent</td><td>Different / absent</td></tr><tr><td>Atomic output + retry</td><td>Built in</td><td>Caller staging</td><td>Caller staging</td><td>Caller staging</td></tr><tr><td>Configurable dialect / typed interfaces</td><td>Fixed byte dialect</td><td>Richer interfaces</td><td>Configurable</td><td>Configurable</td></tr></tbody></table></div><p class="note">Feature probes retain mismatches, including the pinned Rust reader/core accepting a BOM-only prefix as EOF at a 3-byte input boundary. Throughput does not establish equivalent limits, error semantics, allocation/RSS behavior, or a universal fastest implementation.</p></details><p class="note">Measured source <a id="source"></a>. Exact pins, compiler flags, controls and every raw observation accompany the repository report.</p><script>
const rows=DATA, head=HEAD;
const names={'A':'Goose α1 baseline','B':'Goose candidate','rust-csv':'Rust csv 1.4.0','csv-core':'Rust csv-core 0.1.13','simd-csv':'medialab/simd-csv 0.14.0','libcsv':'libcsv + canonical row adapter'};
const colors={'A':'var(--chart-6)','B':'var(--chart-1)','rust-csv':'var(--chart-2)','csv-core':'var(--chart-3)','simd-csv':'var(--chart-4)','libcsv':'var(--chart-5)'};
const fixture=document.getElementById('fixture'),operation=document.getElementById('operation'),chunk=document.getElementById('chunk');
function option(select,value,label){const x=document.createElement('option');x.value=value;x.textContent=label;select.append(x)}
[...new Set(rows.map(x=>x.fixture))].forEach(x=>option(fixture,x,x));fixture.value='mixed-records';
const source=document.getElementById('source');source.textContent=head.slice(0,12);source.href='https://github.com/carabistouflette/goose-csv/tree/'+head;source.target='_blank';source.rel='noopener';
function choices(){const old=chunk.value;chunk.replaceChildren();[...new Set(rows.filter(x=>x.fixture===fixture.value&&x.operation===operation.value).map(x=>x.chunk))].sort((a,b)=>a-b).forEach(x=>option(chunk,x,operation.value==='write'?'Per-record output':x+' bytes'));chunk.value=[...chunk.options].some(x=>x.value===old)?old:'4096';if(!chunk.value)chunk.selectedIndex=0;draw()}
function draw(){const selected=rows.filter(x=>x.fixture===fixture.value&&x.operation===operation.value&&x.chunk===Number(chunk.value));const svg=document.getElementById('plot');svg.replaceChildren();const width=Math.max(300,document.documentElement.clientWidth-18),height=325,span=width-78,maximum=Math.max(...selected.map(x=>x.high))*1.05;svg.setAttribute('viewBox',`0 0 ${width} ${height}`);
function node(tag,attributes,text){const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const[k,v]of Object.entries(attributes))n.setAttribute(k,v);if(text!==undefined)n.textContent=text;svg.append(n);return n}
selected.sort((a,b)=>Object.keys(names).indexOf(a.engine)-Object.keys(names).indexOf(b.engine)).forEach((x,i)=>{const y=19+i*46;node('text',{x:0,y,fill:'var(--foreground)','font-size':13},names[x.engine]);node('rect',{x:0,y:y+8,width:Math.max(1,x.median/maximum*span),height:12,rx:2,fill:colors[x.engine]});const low=x.low/maximum*span,high=x.high/maximum*span;node('line',{x1:low,x2:high,y1:y+14,y2:y+14,stroke:'var(--foreground)','stroke-width':1});for(const xx of[low,high])node('line',{x1:xx,x2:xx,y1:y+10,y2:y+18,stroke:'var(--foreground)','stroke-width':1});node('text',{x:width,y:y+18,fill:'var(--foreground)','text-anchor':'end','font-size':13},x.median.toFixed(1));});node('text',{x:width,y:316,fill:'var(--foreground)','text-anchor':'end','font-size':12},'wire MB/s');const a=selected.find(x=>x.engine==='A'),b=selected.find(x=>x.engine==='B');document.getElementById('caption').textContent=`${b.n} samples per engine · candidate / baseline median throughput: ${(b.median/a.median).toFixed(2)}×. File I/O and setup excluded; complete row materialization/output included.`;}
fixture.onchange=choices;operation.onchange=choices;chunk.onchange=draw;window.addEventListener('resize',draw);choices();
</script></body></html>'''.replace('DATA',data).replace('HEAD',json.dumps(head))
folder=args.output;folder.mkdir(parents=True,exist_ok=True)
(folder/'comparison.html').write_text(html)
(folder/'summary.json').write_text(json.dumps({'source':head,'runs':[str(p) for p in files],'rows':rows},indent=2)+'\n')
print(folder/'comparison.html')
