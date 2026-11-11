package org.nucleantui.android.photos;

import android.database.ContentObserver;
import android.os.Handler;

/**
 * {@link ContentObserver} for AndroidPhotos' APhotoLibrary: MediaStore calls
 * it whenever the images it holds change, and the library reads them again.
 * {@code handle} is the library's NativeHandle; {@link #disarm()} zeroes it
 * before the handle is released. Called on the main Looper only.
 */
public final class MediaObserver extends ContentObserver {
    private long handle;

    public MediaObserver(long handle, Handler handler) {
        super(handler);
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onChange(boolean selfChange) {
        if (handle != 0) {
            nativeOnChange(handle);
        }
    }

    private static native void nativeOnChange(long handle);
}
