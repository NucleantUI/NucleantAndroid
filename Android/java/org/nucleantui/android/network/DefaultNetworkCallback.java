package org.nucleantui.android.network;

import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;

/**
 * Default-network callback for AndroidNetwork's ANetwork. {@code handle} is
 * its NativeHandle; {@link #disarm()} zeroes it before the handle is released.
 * Registered with a main-Looper Handler, so called on the main thread only.
 */
public final class DefaultNetworkCallback extends ConnectivityManager.NetworkCallback {
    private long handle;

    public DefaultNetworkCallback(long handle) {
        this.handle = handle;
    }

    public void disarm() {
        handle = 0;
    }

    @Override
    public void onCapabilitiesChanged(Network network, NetworkCapabilities capabilities) {
        if (handle != 0) {
            nativeOnCapabilitiesChanged(handle, network.getNetworkHandle(), capabilities);
        }
    }

    @Override
    public void onLost(Network network) {
        if (handle != 0) {
            nativeOnLost(handle, network.getNetworkHandle());
        }
    }

    private static native void nativeOnCapabilitiesChanged(long handle, long network, NetworkCapabilities capabilities);

    private static native void nativeOnLost(long handle, long network);
}
