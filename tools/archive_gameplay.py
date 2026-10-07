#!/usr/bin/env python3
"""Archive closed gameplay recordings as lossless RGB video; keep frame indexes."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess


def archive(directory,ffmpeg):
    if (directory/'processes.json').exists():raise RuntimeError('Close both recorded clients before archiving')
    result=[]
    for role in ('host','client'):
        frames=directory/(role+'-frames')
        if not frames.exists():frames=directory/role/'frames'
        if not frames.exists():continue
        rows=list(csv.DictReader((frames/'frames.csv').open()))
        if not rows or any(not (frames/r['file']).is_file() for r in rows):
            raise RuntimeError('Incomplete frame recording: '+role)
        video=directory/(role+'-recording.mkv')
        if video.exists():raise RuntimeError('Existing video must not be overwritten')
        timeline=frames/'timeline.ffconcat'
        lines=['ffconcat version 1.0']
        for i,row in enumerate(rows):
            path=str((frames/row['file']).resolve()).replace("'","'\\''")
            lines.extend(["file '"+path+"'",'option framerate 1000'])
            if i+1<len(rows):lines.append('duration '+str((int(rows[i+1]['time_ms'])-int(row['time_ms']))/1000))
        timeline.write_text('\n'.join(lines)+'\n')
        run=subprocess.run([str(ffmpeg),'-hide_banner','-loglevel','info','-f','concat','-safe','0','-i',str(timeline),
                            '-fps_mode','vfr','-c:v','libx264rgb','-crf','0','-preset','fast','-pix_fmt','bgr24','-threads','2',str(video)],capture_output=True,text=True)
        (directory/(role+'-encoding.log')).write_text(run.stderr)
        counts=re.findall(r'frame=\s*(\d+)',run.stderr)
        if run.returncode or not counts or int(counts[-1])!=len(rows):raise RuntimeError('Video did not preserve the recorded frame count')
        def pixel_hash(source):
            return subprocess.check_output([str(ffmpeg),'-v','error','-i',str(source),'-frames:v','1','-pix_fmt','rgb24','-f','hash','-hash','sha256','-'],text=True).strip()
        if pixel_hash(frames/rows[0]['file'])!=pixel_hash(video):raise RuntimeError('Lossless RGB verification failed')
        result.append({'role':role,'frames':len(rows),'dropped':int(rows[-1]['dropped']),
                       'duration_ms':int(rows[-1]['time_ms'])-int(rows[0]['time_ms']),
                       'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),'first_frame_rgb_verified':True})
        # Key screenshots and per-action JSON remain next to the video.
        # Frame numbers/timestamps remain in frames.csv for exact extraction.
        for row in rows:(frames/row['file']).unlink()
        timeline.unlink()
    (directory/'recordings.json').write_text(json.dumps(result,indent=2))
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('directory',type=Path)
    p.add_argument('--ffmpeg',type=Path,default=shutil.which('ffmpeg'))
    args=p.parse_args()
    if not args.ffmpeg:p.error('Provide --ffmpeg or put ffmpeg on PATH')
    print(json.dumps(archive(args.directory,args.ffmpeg),indent=2))
