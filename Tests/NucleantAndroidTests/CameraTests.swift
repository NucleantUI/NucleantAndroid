import Testing
@testable import AndroidCamera

@Suite struct CameraTests {
    @Test func lensFacingMapsToPosition() {
        #expect(ACameraPosition(lensFacing: 0) == .front)
        #expect(ACameraPosition(lensFacing: 1) == .back)
        #expect(ACameraPosition(lensFacing: 2) == .external)
        #expect(ACameraPosition(lensFacing: 7) == nil)
    }

    let jpegSizes = [(width: 4032, height: 3024), (width: 1920, height: 1080), (width: 1280, height: 720), (width: 640, height: 480)]

    @Test func photoSizeIsTheLargestWithinTheLimit() {
        #expect(ACamera.photoSizeIndex(in: jpegSizes, maxPixelCount: 12_192_768) == 0)
        #expect(ACamera.photoSizeIndex(in: jpegSizes, maxPixelCount: 2_100_000) == 1)
        #expect(ACamera.photoSizeIndex(in: jpegSizes, maxPixelCount: 1_000_000) == 2)
    }

    @Test func photoSizeFallsBackToTheSmallest() {
        #expect(ACamera.photoSizeIndex(in: jpegSizes, maxPixelCount: 1000) == 3)
        #expect(ACamera.photoSizeIndex(in: [], maxPixelCount: 1000) == nil)
    }

    @Test func warmupSizeIsTheSmallestAtLeast320Wide() {
        let yuv = [(width: 176, height: 144), (width: 320, height: 240), (width: 640, height: 480)]
        #expect(ACamera.warmupSizeIndex(in: yuv) == 1)
        #expect(ACamera.warmupSizeIndex(in: [(width: 176, height: 144)]) == 0)
        #expect(ACamera.warmupSizeIndex(in: []) == nil)
    }
}
