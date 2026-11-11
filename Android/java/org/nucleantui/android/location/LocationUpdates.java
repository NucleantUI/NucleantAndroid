package org.nucleantui.android.location;

import android.location.Location;
import android.location.LocationListener;
import android.os.Bundle;

/**
 * {@link LocationListener} for AndroidLocation's ALocation. {@code handle} is
 * its NativeHandle; {@link #disarm()} zeroes it before the handle is released.
 * Requested with the main Looper, so called on the main thread only.
 */
public final class LocationUpdates implements LocationListener {
    private long handle;

    public LocationUpdates(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onLocationChanged(Location location) {
        if (handle != 0) {
            nativeOnLocationChanged(handle, location);
        }
    }

    @Override
    public void onProviderEnabled(String provider) {
        if (handle != 0) {
            nativeOnProviderChanged(handle, provider, true);
        }
    }

    @Override
    public void onProviderDisabled(String provider) {
        if (handle != 0) {
            nativeOnProviderChanged(handle, provider, false);
        }
    }

    // Abstract before Android 10; never called since.
    @Override
    @Deprecated
    public void onStatusChanged(String provider, int status, Bundle extras) {}

    private static native void nativeOnLocationChanged(long handle, Location location);

    private static native void nativeOnProviderChanged(long handle, String provider, boolean enabled);
}
