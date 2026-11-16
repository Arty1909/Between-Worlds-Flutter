"""Compare every response of complete Dart playthroughs with the Python engine."""
import json
import os
from pathlib import Path
import subprocess
import sys
from contextlib import contextmanager
import uuid
import random
import shutil

ROOT=Path(__file__).resolve().parents[2]/'Python'
sys.path.insert(0,str(ROOT))
import engine
from story_edition3 import rewrite_names

@contextmanager
def test_directory():
    directory=ROOT/'.work'/('php-parity-'+uuid.uuid4().hex)
    directory.mkdir()
    try: yield directory
    finally:
        assert directory.resolve().parent==(ROOT/'.work').resolve()
        for file in directory.iterdir(): file.unlink()
        directory.rmdir()

def normalize(view):
    view=json.loads(json.dumps(view,ensure_ascii=False))
    for slot in view['slots']: slot.pop('saved_at',None)
    return view

def main():
    data={k:getattr(engine,v) for k,v in {'nodes':'NODES','characters':'CHARACTERS','chapters':'CHAPTERS','clues':'CLUES','endings':'ENDINGS','hero':'HERO','emotions':'EMOTIONS','looks':'LOOKS','stay_lives':'STAY_LIVES','puzzle_symbols':'PUZZLE_SYMBOLS','puzzle_answer':'PUZZLE_ANSWER','stat_names':'STAT_NAMES'}.items()}
    extras=json.loads((ROOT.parent/'Dart/assets/data/story.json').read_text(encoding='utf-8'))
    data.update({key:extras[key] for key in ['puzzle_results','afterword_remembered']})
    data['flags']=sorted(engine.FLAGS);data['fresh']=engine.fresh_state();runs=[];expected=[];endings=set();seen=set()
    for run in range(12):
        with test_directory() as directory:
            g=engine.Game(directory);commands=[];rng=random.Random(run)
            expected.append({'run':run,'step':-1,'view':normalize(g.view())})
            def act(action,**kwargs):
                payload={'action':action,'revision':g.revision,**kwargs};commands.append(payload)
                try: result={'view':normalize(g.act(payload))}
                except engine.GameError as e: result={'error':str(e)}
                expected.append({'run':run,'step':len(commands)-1,**result})
            act('advance');act('dress',look='lilac');act('new',name='  Арти  Луна  ')
            act('save',slot='1');act('dress',look='moon');act('load',slot='1')
            act('load',slot='../x');act('choose',choice=True);act('advance',revision=-1)
            attempts=0
            while g.view()['kind']!='ending':
                v=g.view();seen.add(v['node'])
                if len(commands)>300: raise AssertionError('Route did not finish')
                if v['can_advance']: act('advance')
                elif v['kind']=='puzzle':
                    if attempts==0: act('puzzle',symbols=['star','moon','leaf'])
                    elif run<4 or run%2: act('puzzle',symbols=engine.PUZZLE_ANSWER)
                    else: act('skip_puzzle')
                    attempts+=1
                else:
                    choices=[c['id'] for c in v['choices'] if c['available']]
                    chosen=rng.choice(choices)
                    if v['node']=='door': chosen=choices[run%len(choices)]
                    if run<4:
                        chosen={'forest_quiz':0,'garden_quiz':1,'moon_quiz':2,'lady':1,'stars':1,'ice':1,'eternity':1,'moon':1,'door':run}.get(v['node'],chosen)
                        if chosen not in choices: chosen=choices[0]
                    act('choose',choice=chosen)
            endings.add(g.state['node']);act('save',slot='3');act('advance');act('new');act('load',slot='3');runs.append(commands)
    dart = (str(Path(os.environ['FLUTTER_ROOT'])/'bin/cache/dart-sdk/bin'/('dart.exe' if os.name=='nt' else 'dart'))
            if os.environ.get('FLUTTER_ROOT') else shutil.which('dart'))
    if dart is None:
        raise RuntimeError('Add Dart to PATH or set FLUTTER_ROOT before running the parity check.')
    result=subprocess.run([dart,str(ROOT.parent/'Dart/tool/parity.dart')],input=json.dumps({'data':rewrite_names(data),'runs':runs},ensure_ascii=False),text=True,encoding='utf-8',capture_output=True)
    if result.returncode: raise RuntimeError(result.stderr)
    actual=[json.loads(x) for x in result.stdout.splitlines()]
    assert len(actual)==len(expected),(len(actual),len(expected),result.stderr)
    for got,want in zip(actual,expected):
        if 'view' in got: got['view']=normalize(got['view'])
        if got!=want:
            (ROOT/'.work/parity-diff.json').write_text(json.dumps({'actual':got,'expected':want},ensure_ascii=False,indent=2),encoding='utf-8')
            raise AssertionError(f"Dart mismatch at run={got['run']}, step={got['step']}; see .work/parity-diff.json")
    assert endings==set(engine.ENDINGS),endings
    print(f'Dart/Python parity: {len(actual)} matching responses, {len(seen)} scenes, all {len(endings)} endings, save/load/dress/errors/puzzle retry.')

if __name__=='__main__': main()
