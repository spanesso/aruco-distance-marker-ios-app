import Foundation

/// Subset of ArUco predefined dictionaries we expose.
///
/// `rawValue` intentionally matches `cv::aruco::PredefinedDictionaryType` from OpenCV.
/// If OpenCV changes those constants, fix the mapping here — Domain stays portable.
enum ArucoDictionary: Int, Sendable {
    case dict4x4_50  = 0
    case dict4x4_100 = 1
    case dict4x4_250 = 2
    case dict5x5_50  = 4
    case dict6x6_50  = 8
    case dict6x6_250 = 10
}
