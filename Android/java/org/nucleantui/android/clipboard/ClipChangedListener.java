package org.nucleantui.android.clipboard;

import android.content.ClipboardManager;

/**
 * {@link ClipboardManager.OnPrimaryClipChangedListener} for AndroidClipboard's
 * AClipboard. {@code handle} is its NativeHandle; {@link #disarm()} zeroes it
 * before the handle is released. Called on the main thread only.
 */
public final class ClipChangedListener implements ClipboardManager.OnPrimaryClipChangedListener {
    private long handle;

    public ClipChangedListener(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onPrimaryClipChanged() {
        if (handle != 0) {
            nativeOnPrimaryClipChanged(handle);
        }
    }

    private static native void nativeOnPrimaryClipChanged(long handle);
}
