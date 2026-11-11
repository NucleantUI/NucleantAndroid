package org.nucleantui.android.camera;

import android.hardware.camera2.CameraDevice;

/**
 * {@link CameraDevice.StateCallback} for AndroidCamera's photo capture.
 *
 * <p>Camera2 reports through abstract classes, which Swift cannot subclass, so
 * each callback is forwarded to a {@code static native} method together with
 * {@code handle} — the Swift capture it belongs to. {@link #disarm()} zeroes the
 * handle once the capture is over; anything Camera2 still delivers after that is
 * dropped here instead of reaching freed Swift memory. Everything runs on the
 * main Looper, so the handle needs no synchronisation.
 */
public final class CameraStateCallback extends CameraDevice.StateCallback {
    private long handle;

    public CameraStateCallback(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onOpened(CameraDevice camera) {
        if (handle != 0) {
            nativeOnOpened(handle, camera);
        } else {
            camera.close();
        }
    }

    @Override
    public void onDisconnected(CameraDevice camera) {
        if (handle != 0) {
            nativeOnDisconnected(handle, camera);
        } else {
            camera.close();
        }
    }

    @Override
    public void onError(CameraDevice camera, int error) {
        if (handle != 0) {
            nativeOnError(handle, camera, error);
        } else {
            camera.close();
        }
    }

    private static native void nativeOnOpened(long handle, CameraDevice camera);

    private static native void nativeOnDisconnected(long handle, CameraDevice camera);

    private static native void nativeOnError(long handle, CameraDevice camera, int error);
}
