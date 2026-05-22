# Fine Camera Calibration

The app uses the intrinsics iOS delivers per frame, which come from Apple's factory calibration. For cases requiring <±3% accuracy, calibrate manually with a chessboard.

## Procedure

1. Print a 9×6 chessboard (internal corners) with 25 mm squares.
   - Generator: https://markhedleyjones.com/projects/calibration-checkerboard-collection
2. Capture 15–20 photos of the chessboard with the native Camera app, from varied angles and distances.
3. Run a Python script with `cv2.calibrateCamera`:

   ```python
   import cv2
   import numpy as np
   import glob

   CHECKERBOARD = (9, 6)
   SQUARE_SIZE_MM = 25.0

   objp = np.zeros((CHECKERBOARD[0] * CHECKERBOARD[1], 3), np.float32)
   objp[:, :2] = np.mgrid[0:CHECKERBOARD[0], 0:CHECKERBOARD[1]].T.reshape(-1, 2)
   objp *= SQUARE_SIZE_MM

   objpoints, imgpoints = [], []
   for fname in glob.glob('calibration/*.jpg'):
       img = cv2.imread(fname)
       gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
       ret, corners = cv2.findChessboardCorners(gray, CHECKERBOARD)
       if ret:
           objpoints.append(objp)
           imgpoints.append(corners)

   ret, K, dist, _, _ = cv2.calibrateCamera(objpoints, imgpoints, gray.shape[::-1], None, None)
   print("K =\n", K)
   print("dist =", dist.ravel())
   ```

4. Replace `CameraIntrinsicsExtractor.extract` to return a hardcoded `K` for your device, and pass `dist` (non-null) to `solvePnP` in `ArucoDetector.mm`.

## Why this isn't integrated in the app

Time budget: this exercise was 4–8 hours. Building in-app chessboard capture, corner detection UI, and the solver would have added ~3 hours. If this were a product, it would be the first follow-up feature.
