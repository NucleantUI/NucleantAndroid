package org.nucleantui.android.speech;

import android.speech.tts.TextToSpeech;
import android.speech.tts.UtteranceProgressListener;

/**
 * TextToSpeech's init and utterance callbacks for AndroidSpeech's
 * ATextToSpeech. {@code handle} is its NativeHandle.
 *
 * <p>Unlike the other helpers, utterance progress arrives on a TTS binder
 * thread, not the main one. So every callback and {@link #disarm()} hold the
 * object's lock: once disarm() returns, no callback is inside Swift and none
 * will enter, and the handle can be released.
 */
public final class SpeechCallbacks extends UtteranceProgressListener implements TextToSpeech.OnInitListener {
    private long handle;

    public SpeechCallbacks(long handle) {
        this.handle = handle;
    }

    public synchronized void disarm() {
        handle = 0;
    }

    @Override
    public synchronized void onInit(int status) {
        if (handle != 0) {
            nativeOnInit(handle, status);
        }
    }

    @Override
    public synchronized void onStart(String utteranceId) {
        if (handle != 0) {
            nativeOnUtterance(handle, utteranceId, 0);
        }
    }

    @Override
    public synchronized void onDone(String utteranceId) {
        if (handle != 0) {
            nativeOnUtterance(handle, utteranceId, 1);
        }
    }

    @Override
    public synchronized void onStop(String utteranceId, boolean interrupted) {
        if (handle != 0) {
            nativeOnUtterance(handle, utteranceId, 2);
        }
    }

    @Override
    @Deprecated
    public synchronized void onError(String utteranceId) {
        if (handle != 0) {
            nativeOnUtterance(handle, utteranceId, 3);
        }
    }

    private static native void nativeOnInit(long handle, int status);

    /** event: 0 started, 1 done, 2 stopped, 3 failed. */
    private static native void nativeOnUtterance(long handle, String utteranceId, int event);
}
