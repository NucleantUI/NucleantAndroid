package org.nucleantui.android;

/**
 * A {@link Runnable} whose body is Swift.
 *
 * <p>{@code handle} is a retained Swift closure (AndroidCore's
 * {@code AndroidMainThread}); {@link #run()} hands it back to Swift, which runs
 * and releases it. Posted to the main {@code Looper} so Swift code can reach the
 * UI thread, which only Java can schedule onto.
 *
 * <p>Runs once: the closure is released by the first {@code run()}.
 */
public final class NativeRunnable implements Runnable {
    private long handle;

    public NativeRunnable(long handle) {
        this.handle = handle;
    }

    @Override
    public void run() {
        long h = handle;
        handle = 0;
        if (h != 0) {
            nativeRun(h);
        }
    }

    private static native void nativeRun(long handle);
}
