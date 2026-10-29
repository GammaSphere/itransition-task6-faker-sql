"""Project Natural Earth 1:110m land polygons to an equal-area SVG symbol.

Behrmann projection (cylindrical equal-area, standard parallels 30°):
    x = lon,  y = sin(lat) * H / 2   with  H = 360 / (pi * cos²30°)
Equal-area means a uniform distribution on the sphere stays uniform on the
map, which is what the app shows for the generated coordinates.

Run:  python tools/build_map.py   (reads data/raw/ne_110m_land.geojson)
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
W = 360.0
H = W / (math.pi * math.cos(math.radians(30)) ** 2)


def project(lon: float, lat: float) -> tuple[float, float]:
    return lon + 180.0, H / 2 - math.sin(math.radians(lat)) * H / 2


def ring_path(ring) -> str:
    points, last = [], None
    for lon, lat in ring:
        x, y = project(lon, lat)
        p = (round(x, 1), round(y, 1))
        if p != last:
            points.append(p)
            last = p
    if len(points) < 3:
        return ""
    return "M" + "L".join(f"{x:g} {y:g}" for x, y in points) + "Z"


def main() -> None:
    data = json.loads((ROOT / "data" / "raw" / "ne_110m_land.geojson").read_text(encoding="utf-8"))
    parts = []
    for feature in data["features"]:
        geom = feature["geometry"]
        polygons = [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]
        for polygon in polygons:
            parts.extend(ring_path(ring) for ring in polygon)
    d = "".join(p for p in parts if p)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg"><symbol id="land" viewBox="0 0 {W:g} {H:.1f}">'
           f'<path d="{d}"/></symbol></svg>\n')
    out = ROOT / "app" / "static" / "land.svg"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(svg, encoding="utf-8")
    print(f"{out.relative_to(ROOT)}: {len(svg)} bytes, H = {H:.3f}")


if __name__ == "__main__":
    main()
