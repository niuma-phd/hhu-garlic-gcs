import QtQuick

/// Geofence helpers shared by the upload check and 开到指定点 (field boundary = inclusion fence).
QtObject {
    property var geoFenceController

    /// There is at least one inclusion polygon or circle
    function hasInclusion() {
        if (!geoFenceController) {
            return false
        }
        for (let i = 0; i < geoFenceController.polygons.count; i++) {
            if (geoFenceController.polygons.get(i).inclusion) return true
        }
        for (let k = 0; k < geoFenceController.circles.count; k++) {
            if (geoFenceController.circles.get(k).inclusion) return true
        }
        return false
    }

    /// Inside an inclusion fence and outside every exclusion fence
    function contains(coordinate) {
        if (!geoFenceController) {
            return false
        }
        let included = false
        for (let i = 0; i < geoFenceController.polygons.count; i++) {
            const polygon = geoFenceController.polygons.get(i)
            const inside = polygon.containsCoordinate(coordinate)
            if (inside && !polygon.inclusion) return false
            if (inside) included = true
        }
        for (let k = 0; k < geoFenceController.circles.count; k++) {
            const circle = geoFenceController.circles.get(k)
            const inside = circle.center.distanceTo(coordinate) <= circle.radius.rawValue
            if (inside && !circle.inclusion) return false
            if (inside) included = true
        }
        return included
    }

    /// Area of the inclusion polygons in m²
    function area() {
        let sum = 0
        if (geoFenceController) {
            for (let i = 0; i < geoFenceController.polygons.count; i++) {
                const polygon = geoFenceController.polygons.get(i)
                if (polygon.inclusion) sum += polygon.area
            }
        }
        return sum
    }
}
