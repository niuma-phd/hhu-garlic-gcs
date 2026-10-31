#pragma once

#include <vector>

/// AB line geometry (AB 线作业). Plain C++ (no Qt) so tools/ab_geometry_test.cc can test it alone.
/// Lines are computed in a local ENU plane with A as origin (WGS-84, through ECEF) and converted back
/// to latitude / longitude in double precision.
namespace hhuab {

struct LatLon {
    double lat = 0;     ///< degrees
    double lon = 0;     ///< degrees
};

struct EN {
    double e = 0;       ///< east, m
    double n = 0;       ///< north, m
};

/// Tangent plane at an origin on the WGS-84 ellipsoid (height 0)
class LocalFrame
{
public:
    explicit LocalFrame(const LatLon &origin);

    EN     toEN(const LatLon &p) const;
    LatLon toLatLon(const EN &p) const;

private:
    double _x0, _y0, _z0;               ///< origin in ECEF
    double _sinLat, _cosLat, _sinLon, _cosLon;
};

struct Line {
    EN start;
    EN end;
};

/// Line k (1-based) is AB moved sideways by (k - 1) × rowWidth to the left (or right) of A→B;
/// odd lines run A→B, even lines B→A (back and forth). a / b in the frame of A.
std::vector<Line> makeLines(const EN &a, const EN &b, double rowWidth, bool left, int count);

/// Unit vector of the line's driving direction
EN direction(const Line &line);
double length(const Line &line);
/// Bearing of the driving direction, degrees 0…360 (0 = north, clockwise)
double bearingDeg(const Line &line);
/// Point on the line's extension `distance` m from the start along the driving direction
/// (negative = before the start)
EN along(const Line &line, double distance);
/// Signed distance of p from the (infinite) line: positive = left of the driving direction
double crossTrack(const Line &line, const EN &p);
/// heading − line bearing, degrees −180…180
double headingError(const Line &line, double headingDeg);

} // namespace hhuab
