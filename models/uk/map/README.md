# The United Kingdom as a map

`regions.geojson` is the map the game draws on the Parliament sheet (stage S18.4,
`client/scripts/country_map.gd`): the nine English regions, Scotland, Wales and Northern
Ireland.

## Source and licence

| | |
|---|---|
| Dataset | International Territorial Level 1 (January 2025) Boundaries UK BUC (ultra generalised, clipped to the coastline) |
| Publisher | Office for National Statistics, Open Geography Portal |
| Page | https://geoportal.statistics.gov.uk/datasets/67ad9f4414934171a08051d408cee70d |
| Licence | Open Government Licence v3.0 (https://www.ons.gov.uk/methodology/geography/licences) |
| Acknowledgement | Source: Office for National Statistics licensed under the Open Government Licence v.3.0. Contains OS data © Crown copyright and database right 2025. |
| Retrieved | 2026-11-28; the download's SHA-256 is in the file (`source_sha256`) |

The acknowledgement is also in the file (`attribution`), and the game shows it at the foot
of How to play whenever the map is on screen.

## How it is made

    python tools/uk/map.py --fetch

downloads the boundaries (on the British National Grid, EPSG:27700, in metres) and runs the
open tool [mapshaper](https://github.com/mbloch/mapshaper) through `npx` (Node.js is
needed; nothing of mapshaper ships with the game). It drops islands under 120 km², thins the
outlines to 3 km (weighted Visvalingam, shared edges kept shared), rounds to 100 m, repairs
what rounding crossed, and writes the regions and the lines between and around them. The
result is 12 regions of 973 points in 34 kB, one feature a line.

## What is in it

| Feature | Properties | Meaning |
|---|---|---|
| Polygon or MultiPolygon | `code`, `name` | A region: its ITL1 code (`TLC` to `TLN`) and name |
| LineString or MultiLineString | `a`, `b` | A line with region `a` on one side and `b` on the other; `b` is empty on the coast |

| Code | Region | The scenario's place |
|---|---|---|
| TLC, TLD, TLE | North East, North West, Yorkshire and The Humber | The North |
| TLF, TLG | East Midlands, West Midlands | The Midlands |
| TLH, TLJ, TLK | East, South East, South West | The South |
| TLI | London | London |
| TLL | Wales | Wales |
| TLM | Scotland | Scotland |
| TLN | Northern Ireland | Northern Ireland |

The places are the scenario's (`[play.web] places`, each with its `regions`), not the
map's: another scenario may group the same twelve regions another way.
`client/tests/map_check.gd` holds that every region is in exactly one place.
