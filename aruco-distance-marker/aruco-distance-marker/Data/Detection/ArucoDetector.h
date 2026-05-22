//
//  ArucoDetector.h
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArucoDetectionResult : NSObject
@property (nonatomic, readonly) NSInteger markerId;
@property (nonatomic, readonly) CGPoint topLeft;
@property (nonatomic, readonly) CGPoint topRight;
@property (nonatomic, readonly) CGPoint bottomRight;
@property (nonatomic, readonly) CGPoint bottomLeft;
@property (nonatomic, readonly) double distanceMeters;
@property (nonatomic, readonly) CGSize imageSize;
@end

@interface ArucoDetector : NSObject

/// dictionaryType maps to cv::aruco::PredefinedDictionaryType.
- (instancetype)initWithDictionaryType:(NSInteger)dictionaryType;

- (NSArray<ArucoDetectionResult *> *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                         intrinsicMatrix:(simd_float3x3)intrinsicMatrix
                                        markerSideMeters:(double)markerSideMeters;

@end

NS_ASSUME_NONNULL_END
