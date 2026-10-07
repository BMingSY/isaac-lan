#!/usr/bin/env python3
"""Bundle existing fixtures into one game, retaining each fixture's assertions."""
import argparse
import hashlib
import json
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]
CASES = [
    ('motion', 'state_motion.lua', 1000),
    # Native white-fire restoration needs an uncleared combat room. Run it
    # before later fixtures consume the fixed first floor's available rooms.
    ('white-fire', 'state_white_fire.lua', 420),
    ('arrival', 'state_arrival.lua', 380),
    ('active-edges', 'state_active_edges.lua', 430),
    ('item-revive', 'state_item_revive.lua', 750),
    ('weapon-charge', 'state_weapon_charge.lua', 320),
    ('peer-intro', 'state_peer_intro.lua', 400),
    ('hourglass', 'state_hourglass.lua', 1400),
    ('special-doors', 'state_special_doors.lua', 510),
    ('floor-items', 'state_floor_items.lua', 1400),
    ('mirror-camera', 'state_mirror_camera.lua', 1250),
]
CHECKPOINTS = {
    'motion': {'moving': 150, 'stopped': 970},
    'arrival': {'joined-combat': 125},
    'active-edges': {'charged-use': 190},
    'item-revive': {'collar-alive': 300, 'dead-cat-alive': 730},
    'weapon-charge': {'charging': 115, 'charged': 205, 'fired': 235},
    'peer-intro': {'guest-intro': 140},
    'hourglass': {'host-rewind': 350, 'guest-rewind': 560, 'floor-rewind': 1230},
    'white-fire': {'white-fire-ghost': 80, 'restored': 300},
    'special-doors': {'devil-entry': 300},
    'floor-items': {'five-pip-floor': 490, 'dice-reset': 705, 'r-key-reset': 1250},
    'mirror-camera': {'large-outward': 185, 'large-return': 285, 'mirror': 720},
}


def build(output):
    bodies, phases, start = [], [], 60
    for name, script, duration in CASES:
        source = (SOURCE / 'tests' / script).read_text()
        phases.append({'name': name, 'start': start, 'duration': duration,
                       'source': script, 'sha256': hashlib.sha256(source.encode()).hexdigest(),
                       'checkpoints': CHECKPOINTS[name]})
        bodies.append("{name=%s,start=%d,duration=%d,load=function()\n%s\nend}" %
                      (json.dumps(name), start, duration, source))
        start += duration + 90
    driver = (SOURCE / 'tests/gameplay_suite_driver.lua').read_text()
    output.write_text(driver.replace('-- BUNDLED_FIXTURES', ',\n'.join(bodies)))
    output.with_suffix('.json').write_text(json.dumps({'phases': phases, 'end_tick': start,
                                                    'game_starts': 1, 'clients': 2}, indent=2) + '\n')
    return phases


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(json.dumps(build(args.output), indent=2))
