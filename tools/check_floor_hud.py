"""Read native HUD ownership through the floor animation in owned game labs."""
import json
from pathlib import Path
import subprocess

SOURCE=Path(__file__).resolve().parents[1]

def windows(path):
    return subprocess.check_output(['wslpath','-w',str(path.resolve())],text=True).strip()

class FloorHudWatch:
    def __init__(self,processes,roles,output):
        self.output=output
        self.readers=[]
        for pid,role in zip(processes,roles):
            path=output/f'{role}-floor-hud.jsonl'
            child=subprocess.Popen(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',
                windows(SOURCE/'tools/lab_hud_state.ps1'),'-GameProcessId',str(pid),
                '-WatchSeconds','90','-OutputFile',windows(path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            self.readers.append((role,path,child))

    def finish(self):
        result={}
        for slot,(role,path,child) in enumerate(self.readers):
            out,error=child.communicate(timeout=15)
            if child.returncode:raise RuntimeError(role+': '+out+error)
            samples=[json.loads(line) for line in path.read_text().splitlines()]
            transition=[s for s in samples if s['stage_transition']!=0]
            if not transition or samples[-1]['stage_transition']!=0:
                raise RuntimeError(role+': native floor animation was not fully observed')
            for sample in samples:
                if sample['primary_controller'] not in (-1,slot+1):
                    raise RuntimeError(f'{role}: HUD changed player during floor transition: {sample}')
                heads=[p['controller'] for p in sample['players'] if p['slot']<4]
                if heads and heads[0]!=slot+1:
                    raise RuntimeError(role+': multiplayer HUD reordered during native loading')
            result[role]={'samples':len(samples),'transition_samples':len(transition),
                          'primary_controller':slot+1,'last_stage':samples[-1]['stage']}
        (self.output/'floor-hud-result.json').write_text(json.dumps(result,indent=2)+'\n')
        return result

    def stop(self):
        for _,_,child in self.readers:
            if child.poll() is None:child.terminate()
            child.communicate(timeout=10)
