package org.nucleantui.android.camera;

import android.media.ImageReader;

/**
 * {@link ImageReader.OnImageAvailableListener} for AndroidCamera's photo
 * capture. {@code stream} tells Swift which of the capture's readers fired (the
 * warm-up frames or the photo). Same handle/disarm scheme as
 * {@link CameraStateCallback}.
 */
public final class ImageAvailableListener implements ImageReader.OnImageAvailableListener {
    private long handle;
    private final int stream;

    public ImageAvailableListener(long handle, int stream) {
        this.handle = handle;
        this.stream = stream;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onImageAvailable(ImageReader reader) {
        if (handle != 0) {
            nativeOnImageAvailable(handle, stream, reader);
        }
    }

    private static native void nativeOnImageAvailable(long handle, int stream, ImageReader reader);
}
