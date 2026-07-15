"""Creature registry for the 64x64 pet art pipeline.

Each creature lives in its own module (tools/art/creatures/<id>.py) exporting
a dict:
    {
        "id": str,
        "name": str,
        "stage_names": [str] * 6,
        "stages": [(jump_frames, sleep_frames, drag, hover)] * 6,
        "broken": [frame, ...],
    }
where every frame is a list of 64 strings of 64 palette characters.
Art tasks import their creature dict here and append it to CREATURES.
"""

from creatures.bird import BIRD
from creatures.bunny import BUNNY
from creatures.flower import FLOWER
from creatures.pig import PIG

CREATURES = [BUNNY, BIRD, FLOWER, PIG]
