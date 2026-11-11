package org.nucleantui.android.flashlight;

import android.hardware.camera2.CameraManager;

/**
 * {@link CameraManager.TorchCallback} for AndroidFlashlight's AFlashlight, so
 * its state follows the torch wherever it is switched (quick settings, other
 * apps). {@code handle} is the AFlashlight's NativeHandle; {@link #disarm()}
 * zeroes it before the handle is released. Called on the main Looper only.
 */
public final class TorchCallback extends CameraManager.TorchCallback {
    private long handle;

    public TorchCallback(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onTorchModeChanged(String cameraId, boolean enabled) {
        if (handle != 0) {
            nativeOnTorchModeChanged(handle, cameraId, enabled);
        }
    }

    @Override
    public void onTorchModeUnavailable(String cameraId) {
        if (handle != 0) {
            nativeOnTorchModeUnavailable(handle, cameraId);
        }
    }

    @Override
    public void onTorchStrengthLevelChanged(String cameraId, int newStrengthLevel) {
        if (handle != 0) {
            nativeOnTorchStrengthLevelChanged(handle, cameraId, newStrengthLevel);
        }
    }

    private static native void nativeOnTorchModeChanged(long handle, String cameraId, boolean enabled);

    private static native void nativeOnTorchModeUnavailable(long handle, String cameraId);

    private static native void nativeOnTorchStrengthLevelChanged(long handle, String cameraId, int level);
}
