package org.nucleantui.android.camera;

import android.hardware.camera2.CameraCaptureSession;

/**
 * {@link CameraCaptureSession.StateCallback} for AndroidCamera's photo
 * capture. Same handle/disarm scheme as {@link CameraStateCallback}.
 */
public final class CaptureSessionCallback extends CameraCaptureSession.StateCallback {
    private long handle;

    public CaptureSessionCallback(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onConfigured(CameraCaptureSession session) {
        if (handle != 0) {
            nativeOnConfigured(handle, session);
        } else {
            session.close();
        }
    }

    @Override
    public void onConfigureFailed(CameraCaptureSession session) {
        if (handle != 0) {
            nativeOnConfigureFailed(handle, session);
        }
    }

    private static native void nativeOnConfigured(long handle, CameraCaptureSession session);

    private static native void nativeOnConfigureFailed(long handle, CameraCaptureSession session);
}
