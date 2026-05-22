import Foundation

enum ArucoConfig {
    /// Physical outer side of the printed marker, in meters.
    /// CALIBRATION: measure the outer black border of the marker with a ruler,
    /// then set this to that measurement (in meters).
    /// Formula: newValue = currentValue × (measuredDistance / reportedDistance)
    static let markerSideMeters: Double = 0.10

    /// ArUco dictionary used by the detector.
    /// DICT_4X4_50: 4×4 bits, 50 unique IDs.
    /// Chosen for low bit density → more robust at low resolution / distance.
    static let dictionary: ArucoDictionary = .dict4x4_50

    /// Informational: ID we expect on the printed marker.
    /// The detector reports whatever IDs it finds; this is just a documentation hint.
    static let expectedMarkerId: Int = 0
}
