package org.nucleantui.android.location;

import android.location.Location;
import android.location.LocationListener;
import android.os.Bundle;
import java.util.function.Consumer;

/**
 * One position request of AndroidLocation's ALocation.requestFix: the
 * Consumer {@code getCurrentLocation} answers (Android 11+), or the listener
 * {@code requestSingleUpdate} answers before that. {@code handle} is the
 * request's NativeHandle; {@link #disarm()} zeroes it before the handle is
 * released. Called on the main thread only.
 */
public final class FixRequest implements LocationListener, Consumer<Location> {
    private long handle;

    public FixRequest(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    /** {@code getCurrentLocation}'s answer; null when no position could be had. */
    @Override
    public void accept(Location location) {
        if (handle != 0) {
            nativeOnFix(handle, location);
        }
    }

    @Override
    public void onLocationChanged(Location location) {
        if (handle != 0) {
            nativeOnFix(handle, location);
        }
    }

    @Override
    public void onProviderEnabled(String provider) {}

    @Override
    public void onProviderDisabled(String provider) {}

    @Override
    @Deprecated
    public void onStatusChanged(String provider, int status, Bundle extras) {}

    private static native void nativeOnFix(long handle, Location location);
}
