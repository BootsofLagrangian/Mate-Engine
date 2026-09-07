#!/usr/bin/env python3
"""Launch a real native Mate text scenario; never simulate native skill execution."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / 'native/tools/run_text_scenario.gd'
PARENT = SCRIPT.with_name('probe_windows_space_skills.gd')


def validate_scenario(value):
    if not isinstance(value, dict) or set(value)-{'version','steps','captures'} or type(value.get('version')) is not int or value['version'] != 1:
        raise ValueError('scenario requires version 1 and steps, optional captures')
    if type(value.get('captures',False)) is not bool:
        raise ValueError('captures must be boolean')
    steps=value.get('steps')
    if not isinstance(steps,list) or not 1 <= len(steps) <= 8:
        raise ValueError('provide 1..8 steps')
    for step in steps:
        if not isinstance(step,dict) or set(step)-{'text','timeout_s','expect_intent','expect_no_intent','expected_outcomes'}:
            raise ValueError('unsupported step fields')
        if not isinstance(step.get('text'),str) or not step['text'].strip() or len(step['text'])>4000:
            raise ValueError('step text must contain 1..4000 characters')
        timeout=step.get('timeout_s',60)
        if isinstance(timeout,bool) or not isinstance(timeout,(int,float)) or not math.isfinite(timeout) or not 1 <= timeout <= 90:
            raise ValueError('timeout_s must be finite 1..90')
        if 'expect_intent' in step and (not isinstance(step['expect_intent'],dict) or not step['expect_intent']):
            raise ValueError('expect_intent is a nonempty subset assertion, never an injected call')
        if type(step.get('expect_no_intent',False)) is not bool:
            raise ValueError('expect_no_intent must be boolean')
        if step.get('expect_no_intent',False) and 'expect_intent' in step:
            raise ValueError('expect_intent and expect_no_intent cannot both be asserted')
        outcomes=step.get('expected_outcomes',['completed','arrived'])
        if not isinstance(outcomes,list) or not outcomes or any(o not in ('completed','arrived','rejected','failed','cancelled','expired','interrupted') for o in outcomes):
            raise ValueError('invalid expected_outcomes')
    return value


def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()


def win_path(path):
    path=str(Path(path).resolve())
    if os.name == 'nt': return path
    return subprocess.check_output(['wslpath','-w',path],text=True).strip()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-exe',required=True,type=Path,help='Actual exported MateCompanion.exe or Windows Godot editor executable')
    parser.add_argument('--project',action='store_true',help='Use local native project with a Windows Godot editor; omit for exported package')
    parser.add_argument('--scenario',required=True,type=Path)
    parser.add_argument('--character',required=True,help='Installed generic character ID')
    parser.add_argument('--output',required=True,type=Path,help='New output directory; previous attempts are never overwritten')
    parser.add_argument('--capture-prompt',action='store_true',help='One-shot exact first-text fixture capture; requires a backend with local diagnostic hook')
    parser.add_argument('--product-defaults',action='store_true',help='Start from product settings defaults, preserving the configured backend endpoint; restore original settings on exit')
    parser.add_argument('--dry-run',action='store_true',help='Validate and print launch command; no native app starts')
    args=parser.parse_args()
    try:scenario=validate_scenario(json.loads(args.scenario.read_text(encoding='utf-8')))
    except (OSError,ValueError) as exc:parser.error(str(exc))
    if not args.native_exe.is_file():parser.error('native executable does not exist')
    if args.output.exists():parser.error('output must be a new directory to preserve prior attempts')
    cmd=[str(args.native_exe.resolve()),'--rendering-driver','d3d12','--rendering-method','forward_plus']
    if args.project:cmd+=['--path',win_path(ROOT/'native')]
    cmd+=['--script',win_path(SCRIPT),'--','--scenario',win_path(args.scenario),'--character',args.character,'--output',win_path(args.output)]
    if args.product_defaults:cmd+=['--product-defaults']
    if args.dry_run:print(json.dumps(cmd,ensure_ascii=False,indent=2));return 0
    args.output.mkdir(parents=True)
    identity={'command':cmd,'scope':'source editor' if args.project else 'exported executable plus external scenario script',
              'executable_sha256':sha(args.native_exe),'script_sha256':sha(SCRIPT),'parent_script_sha256':sha(PARENT),
              'scenario_sha256':sha(args.scenario),'started_unix':time.time(),'character':args.character,
              'settings_profile':'product_defaults' if args.product_defaults else 'saved_settings'}
    (args.output/'launch.json').write_text(json.dumps(identity,indent=2)+'\n')
    capture=None
    if args.capture_prompt:
        capture={'capture_id':uuid.uuid4().hex,'character_id':args.character,
                 'text_sha256':hashlib.sha256(scenario['steps'][0]['text'].strip().encode()).hexdigest(),
                 'expires_unix':time.time()+900}
        marker=ROOT/'user-data/diagnostics/prompt-capture-request.json'
        marker.parent.mkdir(parents=True,exist_ok=True)
        with marker.open('x') as f:json.dump(capture,f)
        identity['prompt_capture_id']=capture['capture_id']
    try:
        with (args.output/'process.log').open('w') as log:
            process=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,cwd=ROOT)
            identity['launcher_child_pid']=process.pid
            (args.output/'launch.json').write_text(json.dumps(identity,indent=2)+'\n')
            # Native owns a 600-second watchdog and restores Settings on normal exit.
            code=process.wait()
    finally:
        if capture:
            source=ROOT/'user-data/diagnostics/prompt-captures'/f"{capture['capture_id']}.json"
            identity['exact_prompt_captured']=source.is_file()
            if source.is_file():
                (args.output/'assembled-prompt.json').write_bytes(source.read_bytes())
            if marker.is_file() and json.loads(marker.read_text()).get('capture_id')==capture['capture_id']:
                marker.unlink()

    identity.update(exit_code=code,finished_unix=time.time())
    (args.output/'launch.json').write_text(json.dumps(identity,indent=2)+'\n')
    report=args.output/'report.json'
    print(json.dumps({'exit_code':code,'report':str(report),'report_exists':report.is_file()}))
    return code if code else (0 if report.is_file() else 1)


if __name__=='__main__':sys.exit(main())
