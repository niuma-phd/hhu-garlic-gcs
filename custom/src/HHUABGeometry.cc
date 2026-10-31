#include "HHUABGeometry.h"

#include <cmath>

namespace hhuab {

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kA  = 6378137.0;                   // WGS-84 semi-major axis
constexpr double kF  = 1.0 / 298.257223563;
constexpr double kE2 = kF * (2.0 - kF);             // first eccentricity squared

double rad(double deg) { return deg * kPi / 180.0; }
double deg(double rad) { return rad * 180.0 / kPi; }

void toEcef(double lat, double lon, double h, double &x, double &y, double &z)
{
    const double sLat = std::sin(rad(lat));
    const double cLat = std::cos(rad(lat));
    const double n = kA / std::sqrt(1.0 - kE2 * sLat * sLat);
    x = (n + h) * cLat * std::cos(rad(lon));
    y = (n + h) * cLat * std::sin(rad(lon));
    z = (n * (1.0 - kE2) + h) * sLat;
}

LatLon fromEcef(double x, double y, double z)
{
    const double p = std::hypot(x, y);
    double lat = std::atan2(z, p * (1.0 - kE2));
    for (int i = 0; i < 10; i++) {
        const double s = std::sin(lat);
        const double n = kA / std::sqrt(1.0 - kE2 * s * s);
        const double h = p / std::cos(lat) - n;
        lat = std::atan2(z, p * (1.0 - kE2 * n / (n + h)));
    }
    return { deg(lat), deg(std::atan2(y, x)) };
}

} // namespace

LocalFrame::LocalFrame(const LatLon &origin)
    : _sinLat(std::sin(rad(origin.lat)))
    , _cosLat(std::cos(rad(origin.lat)))
    , _sinLon(std::sin(rad(origin.lon)))
    , _cosLon(std::cos(rad(origin.lon)))
{
    toEcef(origin.lat, origin.lon, 0, _x0, _y0, _z0);
}

EN LocalFrame::toEN(const LatLon &p) const
{
    double x, y, z;
    toEcef(p.lat, p.lon, 0, x, y, z);
    const double dx = x - _x0, dy = y - _y0, dz = z - _z0;
    return { -_sinLon * dx + _cosLon * dy,
             -_sinLat * _cosLon * dx - _sinLat * _sinLon * dy + _cosLat * dz };
}

LatLon LocalFrame::toLatLon(const EN &p) const
{
    // point of the tangent plane (up = 0); its latitude / longitude is the point below it
    const double x = _x0 - _sinLon * p.e - _sinLat * _cosLon * p.n;
    const double y = _y0 + _cosLon * p.e - _sinLat * _sinLon * p.n;
    const double z = _z0 + _cosLat * p.n;
    return fromEcef(x, y, z);
}

std::vector<Line> makeLines(const EN &a, const EN &b, double rowWidth, bool left, int count)
{
    std::vector<Line> lines;
    const double len = std::hypot(b.e - a.e, b.n - a.n);
    if (len <= 0 || count < 1) {
        return lines;
    }
    const double ue = (b.e - a.e) / len, un = (b.n - a.n) / len;
    // left normal of A→B
    const double side = left ? 1.0 : -1.0;
    const double ne = -un * side, nn = ue * side;
    for (int k = 1; k <= count; k++) {
        const double off = (k - 1) * rowWidth;
        const EN pa { a.e + ne * off, a.n + nn * off };
        const EN pb { b.e + ne * off, b.n + nn * off };
        lines.push_back((k % 2 == 1) ? Line{ pa, pb } : Line{ pb, pa });
    }
    return lines;
}

double length(const Line &line)
{
    return std::hypot(line.end.e - line.start.e, line.end.n - line.start.n);
}

EN direction(const Line &line)
{
    const double len = length(line);
    if (len <= 0) {
        return { 0, 1 };
    }
    return { (line.end.e - line.start.e) / len, (line.end.n - line.start.n) / len };
}

double bearingDeg(const Line &line)
{
    const EN u = direction(line);
    double b = deg(std::atan2(u.e, u.n));
    if (b < 0) {
        b += 360;
    }
    return b;
}

EN along(const Line &line, double distance)
{
    const EN u = direction(line);
    return { line.start.e + u.e * distance, line.start.n + u.n * distance };
}

double crossTrack(const Line &line, const EN &p)
{
    const EN u = direction(line);
    const double de = p.e - line.start.e, dn = p.n - line.start.n;
    // z of u × d: positive when p is left of the driving direction
    return u.e * dn - u.n * de;
}

double headingError(const Line &line, double headingDeg)
{
    double d = std::fmod(headingDeg - bearingDeg(line), 360.0);
    if (d > 180) {
        d -= 360;
    } else if (d < -180) {
        d += 360;
    }
    return d;
}

} // namespace hhuab
