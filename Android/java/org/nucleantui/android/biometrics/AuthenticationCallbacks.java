package org.nucleantui.android.biometrics;

import android.content.DialogInterface;
import android.hardware.biometrics.BiometricPrompt;

/**
 * The prompt's authentication callback and its cancel button, for one
 * authentication of AndroidBiometrics' ABiometrics. {@code handle} is that
 * authentication's NativeHandle; {@link #disarm()} zeroes it before the handle
 * is released. Delivered through the main executor, so on the main thread only.
 */
public final class AuthenticationCallbacks extends BiometricPrompt.AuthenticationCallback
        implements DialogInterface.OnClickListener {
    private long handle;

    public AuthenticationCallbacks(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) {
        if (handle != 0) {
            nativeOnFinished(handle, 0, null);
        }
    }

    @Override
    public void onAuthenticationError(int errorCode, CharSequence errString) {
        if (handle != 0) {
            nativeOnFinished(handle, errorCode, errString == null ? null : errString.toString());
        }
    }

    @Override
    public void onAuthenticationFailed() {
        if (handle != 0) {
            nativeOnAttemptFailed(handle);
        }
    }

    /** The prompt's cancel button. */
    @Override
    public void onClick(DialogInterface dialog, int which) {
        if (handle != 0) {
            nativeOnFinished(handle, -1, null);
        }
    }

    /** code: 0 success, -1 the cancel button, else BiometricPrompt.BIOMETRIC_ERROR_*. */
    private static native void nativeOnFinished(long handle, int code, String message);

    private static native void nativeOnAttemptFailed(long handle);
}
