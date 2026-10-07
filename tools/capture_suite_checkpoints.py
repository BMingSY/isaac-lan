#!/usr/bin/env python3
"""Freeze rendered checkpoints from a completed single-session regression."""
import argparse
import csv
import json
from pathlib import Path
import shutil


def capture(directory, manifest):
    result = json.loads((directory / 'result.json').read_text())
    if not result['pass'] or result.get('close_errors'):
        raise RuntimeError('Finish and close the recorded suite before extracting checkpoints')
    phases = json.loads(manifest.read_text())['phases']
    output = directory / 'checkpoints'
    output.mkdir(exist_ok=False)
    images = []
    for role in ('host', 'client'):
        frames = directory / role / 'frames'
        if not frames.exists():
            continue
        rows = [r for r in csv.DictReader((frames / 'frames.csv').open()) if r['playing'] == '1']
        for phase in phases:
            for name, offset in phase['checkpoints'].items():
                tick = phase['start'] + offset
                row = min(rows, key=lambda r: abs(int(r['tick']) - tick))
                if abs(int(row['tick']) - tick) > 10:
                    raise RuntimeError(f'Missing rendered checkpoint: {role} {phase["name"]} {name}')
                filename = f'{role}-{phase["name"]}-{name}.png'
                shutil.copy2(frames / row['file'], output / filename)
                images.append({'file': filename, 'role': role, 'phase': phase['name'],
                               'requested_tick': tick, 'frame': row})
    if not images:
        raise RuntimeError('Suite did not record native frames')
    (output / 'index.json').write_text(json.dumps({'images': images, 'visual_review_required': True}, indent=2) + '\n')
    return images


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--manifest', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(capture(args.directory, args.manifest), indent=2))
