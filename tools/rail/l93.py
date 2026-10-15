"""Lambert-93 (EPSG:2154) conversion for the rail tools, without pyproj.

The map's coordinates are Lambert-93 minus ORIGIN (metres, x east, y north): fwd(lat, lon) gives them for a WGS84
point (GRS80 and WGS84 differ by under a millimetre here), inv(x, y) goes back. Formulas: IGN, "Projection
cartographique conique conforme de Lambert" (NT/G 71), secant cone through 44° and 49° N, origin 46.5° N 3° E,
false easting 700 km, false northing 6,600 km.
"""
import math

ORIGIN = (641117.6, 6846184.3)          # Télécom Paris, the map's origin (world.json meta.origin)

_A = 6378137.0                          # GRS80
_F = 1 / 298.257222101
_E = math.sqrt(2 * _F - _F * _F)
_LAT0, _LON0 = math.radians(46.5), math.radians(3.0)
_P1, _P2 = math.radians(49.0), math.radians(44.0)
_X0, _Y0 = 700000.0, 6600000.0


def _m(p: float) -> float:
    return math.cos(p) / math.sqrt(1 - (_E * math.sin(p)) ** 2)


def _t(p: float) -> float:
    return math.tan(math.pi / 4 - p / 2) / ((1 - _E * math.sin(p)) / (1 + _E * math.sin(p))) ** (_E / 2)


_N = (math.log(_m(_P1)) - math.log(_m(_P2))) / (math.log(_t(_P1)) - math.log(_t(_P2)))
_FF = _m(_P1) / (_N * _t(_P1) ** _N)
_R0 = _A * _FF * _t(_LAT0) ** _N


def fwd(lat: float, lon: float) -> tuple:
    """WGS84 degrees -> map metres (Lambert-93 minus ORIGIN)."""
    r = _A * _FF * _t(math.radians(lat)) ** _N
    th = _N * (math.radians(lon) - _LON0)
    return _X0 + r * math.sin(th) - ORIGIN[0], _Y0 + _R0 - r * math.cos(th) - ORIGIN[1]


def inv(x: float, y: float) -> tuple:
    """Map metres -> WGS84 degrees (lat, lon), iterating the isometric latitude."""
    dx = x + ORIGIN[0] - _X0
    dy = _R0 - (y + ORIGIN[1] - _Y0)
    r = math.copysign(math.hypot(dx, dy), _N)
    th = math.atan2(dx, dy)
    t = (r / (_A * _FF)) ** (1 / _N)
    lon = th / _N + _LON0
    lat = math.pi / 2 - 2 * math.atan(t)
    for _ in range(12):
        es = _E * math.sin(lat)
        lat = math.pi / 2 - 2 * math.atan(t * ((1 - es) / (1 + es)) ** (_E / 2))
    return math.degrees(lat), math.degrees(lon)
