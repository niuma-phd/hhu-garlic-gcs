// AB line geometry test (AB 线作业): spacing, back-and-forth direction, left / right, lat/lon round trip.
// Build alone, without Qt:  cl /EHsc /O2 /I..\src ab_geometry_test.cc ..\src\HHUABGeometry.cc
#include "HHUABGeometry.h"

#include <cmath>
#include <cstdio>

using namespace hhuab;

static int failures = 0;

static void check(bool ok, const char *what, double value)
{
    std::printf("%s  %-48s %.6g\n", ok ? "PASS" : "FAIL", what, value);
    if (!ok) {
        failures++;
    }
}

int main()
{
    // near 32° N (the playground of the SITL home), AB about 80 m to the north-east
    const LatLon a { 31.93778228, 118.7901755 };
    const LocalFrame frame(a);
    const LatLon bLL { 31.93830000, 118.7907000 };
    const EN b = frame.toEN(bLL);

    // round trip lat/lon -> EN -> lat/lon, over the field size
    double worst = 0;
    for (int i = -10; i <= 10; i++) {
        for (int j = -10; j <= 10; j++) {
            const LatLon p { a.lat + i * 0.0002, a.lon + j * 0.0002 };     // ±220 m
            const LatLon q = frame.toLatLon(frame.toEN(p));
            const EN d = LocalFrame(p).toEN(q);
            worst = std::fmax(worst, std::hypot(d.e, d.n));
        }
    }
    check(worst < 0.001, "lat/lon round trip error < 1 mm (m)", worst);

    // 0.25 m rows, 10 lines, both sides
    for (int left = 1; left >= 0; left--) {
        const std::vector<Line> lines = makeLines({ 0, 0 }, b, 0.25, left == 1, 10);
        check(lines.size() == 10, left ? "left: 10 lines" : "right: 10 lines", lines.size());

        // spacing measured on the lat/lon of the lines (what is uploaded), not on the plane
        double spacingErr = 0;
        for (size_t k = 1; k < lines.size(); k++) {
            const LatLon s0 = frame.toLatLon(lines[k - 1].start);
            const LatLon s1 = frame.toLatLon(lines[k].start);
            const LatLon e1 = frame.toLatLon(lines[k].end);
            const LocalFrame f0(s0);
            const Line prevLine { f0.toEN(s0), f0.toEN(frame.toLatLon(lines[k - 1].end)) };
            const double d1 = std::fabs(crossTrack(prevLine, f0.toEN(s1)));
            const double d2 = std::fabs(crossTrack(prevLine, f0.toEN(e1)));
            spacingErr = std::fmax(spacingErr, std::fmax(std::fabs(d1 - 0.25), std::fabs(d2 - 0.25)));
        }
        check(spacingErr < 0.001, left ? "left: neighbour spacing error < 1 mm (m)" : "right: neighbour spacing error < 1 mm (m)", spacingErr);

        // odd lines A→B, even lines B→A
        const double b1 = bearingDeg(lines[0]);
        bool dirOk = true;
        for (size_t k = 0; k < lines.size(); k++) {
            const double diff = std::fabs(headingError(lines[k], b1));
            dirOk = dirOk && ((k % 2 == 0) ? diff < 1e-9 : std::fabs(diff - 180) < 1e-9);
        }
        check(dirOk, "odd lines A->B, even lines B->A", b1);

        // line 1 is AB itself; line 2 lies left (right) of A→B
        check(std::hypot(lines[0].start.e, lines[0].start.n) < 1e-9 && std::hypot(lines[0].end.e - b.e, lines[0].end.n - b.n) < 1e-9,
              "line 1 = AB", 0);
        const double side = crossTrack(lines[0], lines[1].start);
        check(left ? side > 0.2499 : side < -0.2499, left ? "line 2 left of A->B (m)" : "line 2 right of A->B (m)", side);
        const double side10 = crossTrack(lines[0], lines[9].end);
        check(std::fabs(std::fabs(side10) - 2.25) < 1e-9, "line 10 offset 9 x 0.25 m (m)", side10);
    }

    // lead-in points before the start
    const Line l = makeLines({ 0, 0 }, b, 0.25, true, 1)[0];
    const EN lead = along(l, -6.0);
    check(std::fabs(crossTrack(l, lead)) < 1e-9 && std::fabs(std::hypot(lead.e, lead.n) - 6.0) < 1e-9, "lead point 6 m before start on the line", 0);

    std::printf("%s (%d failures)\n", failures == 0 ? "ALL PASS" : "FAILED", failures);
    return failures == 0 ? 0 : 1;
}
