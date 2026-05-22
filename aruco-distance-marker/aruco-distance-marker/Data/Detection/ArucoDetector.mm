//
//  ArucoDetector.mm
//

// OpenCV headers MUST come before any Apple headers.
// Apple defines NO/YES as Objective-C macros; several OpenCV headers use NO/YES
// as C++ identifiers and will fail to parse if those macros are already defined.
#ifdef __cplusplus
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/objdetect/aruco_detector.hpp>
#import <opencv2/objdetect/aruco_dictionary.hpp>
#import <opencv2/calib3d.hpp>
#endif

#import "ArucoDetector.h"

@implementation ArucoDetectionResult {
    NSInteger _markerId;
    CGPoint _topLeft, _topRight, _bottomRight, _bottomLeft;
    double _distanceMeters;
    CGSize _imageSize;
}

- (instancetype)initWithId:(NSInteger)markerId
                   topLeft:(CGPoint)tl
                  topRight:(CGPoint)tr
               bottomRight:(CGPoint)br
                bottomLeft:(CGPoint)bl
                  distance:(double)distance
                 imageSize:(CGSize)imageSize {
    if ((self = [super init])) {
        _markerId = markerId;
        _topLeft = tl;
        _topRight = tr;
        _bottomRight = br;
        _bottomLeft = bl;
        _distanceMeters = distance;
        _imageSize = imageSize;
    }
    return self;
}

- (NSInteger)markerId { return _markerId; }
- (CGPoint)topLeft { return _topLeft; }
- (CGPoint)topRight { return _topRight; }
- (CGPoint)bottomRight { return _bottomRight; }
- (CGPoint)bottomLeft { return _bottomLeft; }
- (double)distanceMeters { return _distanceMeters; }
- (CGSize)imageSize { return _imageSize; }
@end


@implementation ArucoDetector {
    cv::aruco::ArucoDetector _detector;
    cv::aruco::Dictionary _dictionary;
    cv::aruco::DetectorParameters _params;
}

- (instancetype)initWithDictionaryType:(NSInteger)dictionaryType {
    if ((self = [super init])) {
        cv::aruco::PredefinedDictionaryType type =
            static_cast<cv::aruco::PredefinedDictionaryType>(dictionaryType);
        _dictionary = cv::aruco::getPredefinedDictionary(type);
        _params = cv::aruco::DetectorParameters();
        _params.cornerRefinementMethod = cv::aruco::CORNER_REFINE_SUBPIX;
        _detector = cv::aruco::ArucoDetector(_dictionary, _params);
    }
    return self;
}

- (NSArray<ArucoDetectionResult *> *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         intrinsicMatrix:(simd_float3x3)intrinsicMatrix
                                        markerSideMeters:(double)markerSideMeters {
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    void *base = CVPixelBufferGetBaseAddress(pixelBuffer);

    cv::Mat bgra(static_cast<int>(height), static_cast<int>(width), CV_8UC4, base, bytesPerRow);
    cv::Mat gray;
    cv::cvtColor(bgra, gray, cv::COLOR_BGRA2GRAY);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    std::vector<int> ids;
    std::vector<std::vector<cv::Point2f>> corners;
    std::vector<std::vector<cv::Point2f>> rejected;
    _detector.detectMarkers(gray, corners, ids, rejected);

    if (ids.empty()) { return @[]; }

    // simd_float3x3 is column-major; cv::Mat is row-major. Transpose mapping below.
    cv::Mat cameraMatrix = (cv::Mat_<double>(3, 3) <<
        intrinsicMatrix.columns[0].x, intrinsicMatrix.columns[1].x, intrinsicMatrix.columns[2].x,
        intrinsicMatrix.columns[0].y, intrinsicMatrix.columns[1].y, intrinsicMatrix.columns[2].y,
        intrinsicMatrix.columns[0].z, intrinsicMatrix.columns[1].z, intrinsicMatrix.columns[2].z
    );
    cv::Mat distCoeffs = cv::Mat::zeros(4, 1, CV_64F);

    // Object points: marker centered at origin in plane Z=0.
    // Order MUST match ArUco corner order (TL, TR, BR, BL) for SOLVEPNP_IPPE_SQUARE.
    const float s = static_cast<float>(markerSideMeters);
    std::vector<cv::Point3f> objectPoints = {
        cv::Point3f(-s / 2.0f,  s / 2.0f, 0.0f),
        cv::Point3f( s / 2.0f,  s / 2.0f, 0.0f),
        cv::Point3f( s / 2.0f, -s / 2.0f, 0.0f),
        cv::Point3f(-s / 2.0f, -s / 2.0f, 0.0f)
    };

    NSMutableArray<ArucoDetectionResult *> *results = [NSMutableArray arrayWithCapacity:ids.size()];

    for (size_t i = 0; i < ids.size(); ++i) {
        cv::Mat rvec, tvec;
        const bool ok = cv::solvePnP(
            objectPoints, corners[i],
            cameraMatrix, distCoeffs,
            rvec, tvec,
            false, cv::SOLVEPNP_IPPE_SQUARE
        );
        if (!ok) continue;

        const double tx = tvec.at<double>(0, 0);
        const double ty = tvec.at<double>(1, 0);
        const double tz = tvec.at<double>(2, 0);
        const double distance = std::sqrt(tx * tx + ty * ty + tz * tz);

        ArucoDetectionResult *r = [[ArucoDetectionResult alloc]
            initWithId:ids[i]
               topLeft:CGPointMake(corners[i][0].x, corners[i][0].y)
              topRight:CGPointMake(corners[i][1].x, corners[i][1].y)
           bottomRight:CGPointMake(corners[i][2].x, corners[i][2].y)
            bottomLeft:CGPointMake(corners[i][3].x, corners[i][3].y)
              distance:distance
             imageSize:CGSizeMake(static_cast<CGFloat>(width), static_cast<CGFloat>(height))];
        [results addObject:r];
    }

    return results;
}

@end
