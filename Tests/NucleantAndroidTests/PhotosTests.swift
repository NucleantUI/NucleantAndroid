import Testing
@testable import AndroidPhotos

@Suite struct PhotoPermissionsTests {
    let images = APhotoLibrary.readMediaImages
    let selected = APhotoLibrary.readMediaVisualUserSelected
    let storage = APhotoLibrary.readExternalStorage

    @Test func requestedPermissionsFollowTheSDKLevel() {
        #expect(APhotoLibrary.permissions(sdkLevel: 29) == [storage])
        #expect(APhotoLibrary.permissions(sdkLevel: 32) == [storage])
        #expect(APhotoLibrary.permissions(sdkLevel: 33) == [images])
        #expect(APhotoLibrary.permissions(sdkLevel: 34) == [images, selected])
        #expect(APhotoLibrary.permissions(sdkLevel: 36) == [images, selected])
    }

    @Test func fullAccessBeforeAndroid13() {
        #expect(APhotoLibrary.authorization(sdkLevel: 30, granted: [storage: true]) == .authorized)
        #expect(APhotoLibrary.authorization(sdkLevel: 30, granted: [storage: false]) == .denied)
        #expect(APhotoLibrary.authorization(sdkLevel: 30, granted: [:]) == .denied)
    }

    @Test func android13HasNoPartialAccess() {
        #expect(APhotoLibrary.authorization(sdkLevel: 33, granted: [images: true]) == .authorized)
        #expect(APhotoLibrary.authorization(sdkLevel: 33, granted: [images: false, selected: true]) == .denied)
    }

    @Test func android14SelectedPhotosIsLimited() {
        #expect(APhotoLibrary.authorization(sdkLevel: 34, granted: [images: true, selected: true]) == .authorized)
        #expect(APhotoLibrary.authorization(sdkLevel: 34, granted: [images: false, selected: true]) == .limited)
        #expect(APhotoLibrary.authorization(sdkLevel: 34, granted: [images: false, selected: false]) == .denied)
    }
}
