package org.nucleantui.android.sensors;

import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;

/**
 * {@link SensorEventListener} for one of AndroidSensors' ASensor objects.
 * {@code handle} is its NativeHandle; {@link #disarm()} zeroes it before the
 * handle is released. Registered with a main-Looper Handler, so called on the
 * main thread only.
 */
public final class SensorListener implements SensorEventListener {
    private long handle;

    public SensorListener(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (handle != 0) {
            nativeOnSensorChanged(handle, event.values, event.accuracy, event.timestamp);
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        if (handle != 0) {
            nativeOnAccuracyChanged(handle, accuracy);
        }
    }

    private static native void nativeOnSensorChanged(long handle, float[] values, int accuracy, long timestamp);

    private static native void nativeOnAccuracyChanged(long handle, int accuracy);
}
