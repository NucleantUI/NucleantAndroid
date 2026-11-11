package org.nucleantui.android.battery;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Receives the battery and power-saver broadcasts for AndroidBattery's
 * ABattery. {@code handle} is its NativeHandle; {@link #disarm()} zeroes it
 * before the handle is released. Registered with a main-Looper Handler, so
 * called on the main thread only.
 */
public final class BatteryReceiver extends BroadcastReceiver {
    private long handle;

    public BatteryReceiver(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (handle != 0) {
            nativeOnReceive(handle, intent);
        }
    }

    private static native void nativeOnReceive(long handle, Intent intent);
}
