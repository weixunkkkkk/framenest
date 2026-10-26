#!/usr/bin/env python3
"""Compare cold-path and cached media analysis over the real stdio MCP interface."""
import argparse
import json
import shutil
import statistics
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from test_mcp import JSONLineClient


def run(binary, fixtures, trials):
    files = sorted(p for p in fixtures.rglob('*') if p.is_file() and p.suffix.lower() in {'.mp4', '.mov', '.png', '.jpg', '.jpeg'})
    if not 1 <= len(files) <= 20:
        raise ValueError('Use 1–20 image/video fixtures.')
    samples = []
    for trial in range(trials):
        with tempfile.TemporaryDirectory(prefix='framenest-benchmark-') as name:
            root = Path(name).resolve()
            for source in files:
                target = root / source.relative_to(fixtures)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
            client = JSONLineClient([str(binary.resolve())])
            peak_kb = [0]
            done = threading.Event()
            def monitor():
                while not done.wait(0.15):
                    output = subprocess.run(['ps', '-p', str(client.process.pid), '-o', 'rss='], capture_output=True, text=True).stdout.strip()
                    if output.isdigit(): peak_kb[0] = max(peak_kb[0], int(output))
            watcher = threading.Thread(target=monitor, daemon=True)
            watcher.start()
            try:
                client.request('initialize', {'protocolVersion':'2025-11-25', 'capabilities':{}, 'clientInfo':{'name':'framenest-benchmark','version':'1'}})
                client.send({'jsonrpc':'2.0','method':'notifications/initialized'})
                arguments = {'paths':[str(root / p.relative_to(fixtures)) for p in files]}
                def analyze():
                    response = client.request('tools/call', {'name':'analyze_media','arguments':arguments}, timeout=180)['result']
                    assert not response.get('isError'), response
                    return response.get('structuredContent') or json.loads(response['content'][0]['text'])
                start = time.perf_counter(); first = analyze(); cold = time.perf_counter()-start
                start = time.perf_counter(); second = analyze(); warm = time.perf_counter()-start
                assert all(i['visual_analysis']['cacheHit'] for i in second['items'])
                sample = {'cold_seconds':round(cold,4), 'cached_seconds':round(warm,4), 'peak_rss_mb':round(peak_kb[0]/1024,1),
                          'categories':{Path(i['path']).name:i['category'] for i in first['items']},
                          'ocr_frames':sum(i['visual_analysis']['ocrFrames'] for i in first['items']) if all(i['visual_analysis'].get('ocrFrames') is not None for i in first['items']) else None}
                samples.append(sample)
                print(json.dumps({'trial':trial+1, **sample},ensure_ascii=False),flush=True)
            finally:
                client.close(); done.set(); watcher.join(timeout=2)
    return {'fixture_count':len(files), 'trials':trials, 'samples':samples,
            'median_cold_seconds':statistics.median(x['cold_seconds'] for x in samples),
            'median_cached_seconds':statistics.median(x['cached_seconds'] for x in samples),
            'peak_rss_mb':max(x['peak_rss_mb'] for x in samples)}


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--binary',type=Path,required=True)
    parser.add_argument('--fixtures',type=Path,required=True)
    parser.add_argument('--trials',type=int,default=3,choices=range(1,11))
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=run(args.binary,args.fixtures,args.trials)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print('SUMMARY',json.dumps({k:v for k,v in result.items() if k!='samples'},ensure_ascii=False),flush=True)
