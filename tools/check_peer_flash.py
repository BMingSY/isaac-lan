#!/usr/bin/env python3
"""Screen a stationary host's recorded pixels during native guest door cycles.

Only the peer-flash fixture is supported. The result certifies recorded samples;
frame gaps and writer drops remain explicit, and pixels still need visual review.
"""
import argparse
import csv
import json
from pathlib import Path
import statistics
import subprocess


def check(directory, ffmpeg):
    root=directory/'host/frames'
    all_rows=list(csv.DictReader((root/'frames.csv').open()))
    rows=[r for r in all_rows if r['playing']=='1' and r['room']=='84' and 60<=int(r['tick'])<=620]
    if len(rows)<200:raise RuntimeError('Too few stationary in-game frames')
    timeline=root/'review.ffconcat'
    lines=['ffconcat version 1.0']
    for index,row in enumerate(rows):
        path=str((root/row['file']).resolve()).replace("'","'\\''")
        lines.extend(["file '"+path+"'",'option framerate 1000'])
        if index+1<len(rows):lines.append('duration '+str((int(rows[index+1]['time_ms'])-int(row['time_ms']))/1000))
    timeline.write_text('\n'.join(lines)+'\n')
    raw=subprocess.check_output([str(ffmpeg),'-v','error','-f','concat','-safe','0','-i',str(timeline),
        '-vf','crop=iw*.4:ih*.4:iw*.3:ih*.3,scale=32:32','-fps_mode','vfr','-pix_fmt','gray','-f','rawvideo','-'])
    if len(raw)!=len(rows)*1024:raise RuntimeError('Pixel frame count differs from time index')
    means=[sum(raw[i*1024:(i+1)*1024])/1024 for i in range(len(rows))]
    median=statistics.median(means)
    candidates=[{'file':row['file'],'tick':int(row['tick']),'time_ms':int(row['time_ms']),'mean':round(mean,3)}
        for row,mean in zip(rows,means) if mean<median*.15 or mean>min(240,median+100)]
    gaps=[int(b['time_ms'])-int(a['time_ms']) for a,b in zip(rows,rows[1:])]
    result={'pass':not candidates,'frames':len(rows),'tick_range':[rows[0]['tick'],rows[-1]['tick']],
        'sample_interval_median_ms':statistics.median(gaps),'largest_gap_ms':max(gaps),
        'writer_drops':int(all_rows[-1]['dropped']),'mean_range':[round(min(means),3),round(max(means),3)],
        'flash_candidates':candidates,'visual_review_required':True,'scope':'Recorded stationary host frames during six native guest door entries.'}
    (directory/'flash-review.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path);parser.add_argument('--ffmpeg',type=Path,required=True)
    args=parser.parse_args();result=check(args.directory,args.ffmpeg)
    print(json.dumps(result,indent=2));raise SystemExit(0 if result['pass'] else 1)
