#!/usr/bin/env python3
"""Make automatic filmstrips and flag dark scene frames around peer door entries.

Candidates require visual review. This does not certify all rendering or catch
flashes shorter than the isolated recorder's sampling interval.
"""
import argparse
import csv
import json
from pathlib import Path
import re
import shutil
import statistics
import subprocess


def review(directory,ffmpeg):
    if (directory/'processes.json').exists():
        raise RuntimeError('Close both clients before reviewing the recordings')
    actions=[json.loads(line) for line in (directory/'actions.jsonl').read_text().splitlines()]
    previous={};checks=[]
    for action in actions:
        if action['action']!='capture':continue
        role=action['role'];state=action['state'];old=previous.get(role)
        previous[role]=state
        entry=re.search(r'-(host|client)-door-[0-7]-',action['name'])
        if not entry or role==entry[1] or not old:continue
        if (old.get('stage'),old.get('room'))!=(state.get('stage'),state.get('room')):continue
        if state.get('phase')!=3 or state.get('pause'):continue
        rows=list(csv.DictReader((directory/(role+'-frames')/'frames.csv').open()))
        index=next(i for i,r in enumerate(rows) if int(r['sequence'])==action['recorded_frame'])
        center=int(rows[index]['time_ms'])
        chosen=[i for i,r in enumerate(rows) if center-2000<=int(r['time_ms'])<=center+400]
        first,last=chosen[0],chosen[-1]
        video=directory/(role+'-recording.mkv')
        if not video.exists():raise RuntimeError('Archive the recording first: '+role)
        select=f'select=between(n\\,{first}\\,{last})'
        # Small actual-pixel samples make scene darkness measurable without
        # extra imaging packages. Exclude the HUD and the border vignette.
        pixels=subprocess.check_output([str(ffmpeg),'-v','error','-i',str(video),
            '-vf',select+',crop=iw*.6:ih*.6:iw*.2:ih*.2,scale=96:54',
            '-fps_mode','vfr','-pix_fmt','rgb24','-f','rawvideo','-'])
        size=96*54*3
        if len(pixels)!=len(chosen)*size:raise RuntimeError('Review frame count differs from the recording')
        means=[sum(pixels[i*size:(i+1)*size])/size for i in range(len(chosen))]
        median=statistics.median(means)
        candidates=[{'index':chosen[i],'sequence':int(rows[chosen[i]]['sequence']),
            'time_ms':int(rows[chosen[i]]['time_ms']),'mean_rgb':round(mean,3)}
            for i,mean in enumerate(means) if mean<8 and median>max(20,mean*5)]
        stem=Path(action['name']).stem+'-filmstrip';sheet=directory/(stem+'.png')
        columns=4;lines=(len(chosen)+columns-1)//columns
        subprocess.run([str(ffmpeg),'-v','error','-i',str(video),'-vf',
            select+f',scale=320:180,tile={columns}x{lines}',
            '-frames:v','1','-update','1','-y',str(sheet)],check=True)
        check={'event':action['name'],'viewer':role,'mover':entry[1],
            'stage':state['stage'],'room':state['room'],'filmstrip':sheet.name,
            'first_index':first,'last_index':last,'order':'row-major, left to right',
            'frames':[{'index':i,'sequence':int(rows[i]['sequence']),
                'time_ms':int(rows[i]['time_ms']),'mean_rgb':round(means[j],3)} for j,i in enumerate(chosen)],
            'dark_frame_candidates':candidates}
        (directory/(stem+'.json')).write_text(json.dumps(check,indent=2));checks.append(check)
    result={'checks':checks,'dark_frame_candidates':sum(len(c['dark_frame_candidates']) for c in checks),
        'visual_review_required':True,
        'scope':'Peer door entries while this viewer stays in the same room; recorded samples only.'}
    (directory/'visual-candidates.json').write_text(json.dumps(result,indent=2))
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path)
    p.add_argument('--ffmpeg',type=Path,default=shutil.which('ffmpeg'))
    args=p.parse_args()
    if not args.ffmpeg:p.error('Provide --ffmpeg or put ffmpeg on PATH')
    result=review(args.directory,args.ffmpeg)
    print(json.dumps({'checks':len(result['checks']),'dark_frame_candidates':result['dark_frame_candidates']}))
