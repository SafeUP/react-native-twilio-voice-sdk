package com.happytheapp.react.RNTwilioVoiceSDK;

import android.bluetooth.BluetoothAdapter;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.util.Log;

import com.facebook.react.bridge.ReactApplicationContext;


/*
 * Needed for setting/abandoning audio focus during a call
 */
public class AudioFocusManager implements BluetoothInterface {
    private AudioManager audioManager;
    private int originalAudioMode = AudioManager.MODE_NORMAL;
    private AudioFocusRequest focusRequest;
    private  BluetoothAdapter bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
    private boolean isConnected = false;
    public AudioFocusManager(ReactApplicationContext reactContext, TwilioVoiceSDKModule twilioVoiceSDKModule) {
        audioManager = (AudioManager) reactContext.getSystemService(Context.AUDIO_SERVICE);
        twilioVoiceSDKModule.setBluetoothInterface(this);
    }


    public boolean isConnected() {
        return isConnected;
    }

    public void setConnected(boolean connected) {
        isConnected = connected;
    }

    public void setAudioFocus() {
        if (audioManager == null) {
            return;
        }

        originalAudioMode = audioManager.getMode();
        // Request audio focus before making any device switch
        if (Build.VERSION.SDK_INT >= 26) {
            AudioAttributes playbackAttributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build();
            focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                    .setAudioAttributes(playbackAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener(new AudioManager.OnAudioFocusChangeListener() {
                        @Override
                        public void onAudioFocusChange(int i) { }
                    })
                    .build();
            audioManager.requestAudioFocus(focusRequest);
        } else {
            audioManager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_VOICE_CALL,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            );
        }
        /*
         * Start by setting MODE_IN_COMMUNICATION as default audio mode. It is
         * required to be in this mode when playout and/or recording starts for
         * best possible VoIP performance. Some devices have difficulties with speaker mode
         * if this is not set.
         */



        audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
        onStartBluetoothSCO();
        if(isConnected()){
            initAudioBluetooth();
            handleBluetooth();
        }


    }


    public void unsetAudioFocus() {
        if (audioManager == null) {
            return;
        }

        audioManager.setMode(AudioManager.MODE_NORMAL);

        if (Build.VERSION.SDK_INT >= 26) {
            if (focusRequest != null) {
                audioManager.abandonAudioFocusRequest(focusRequest);
            }
        } else {
            audioManager.abandonAudioFocus(null);
        }
        onStartBluetoothSCO();
    }

    public void setSpeakerPhone(Boolean value) {
        // TODO check whether it is necessary to call setAudioFocus again
        // setAudioFocus();
        if(!bluetoothAdapter.isEnabled()){ //When bluetooth enable, can't turn on speaker
            audioManager.setSpeakerphoneOn(value);
        }

    }

    private void handleBluetooth(){
        if(bluetoothAdapter.isEnabled() && audioManager != null){
            audioManager.setBluetoothScoOn(true);
        }else if (!bluetoothAdapter.isEnabled() && audioManager != null){
            resetSco();

        }
    }

    private void resetSco()
    {
        if(bluetoothAdapter.isEnabled()){
            audioManager.setMode(AudioManager.MODE_NORMAL);
            audioManager.stopBluetoothSco();
            audioManager.setBluetoothScoOn(false);
            audioManager.setSpeakerphoneOn(false);
            audioManager.setWiredHeadsetOn(false);
        }

    }

    @Override
    public void onBluetoothConnected() {
        setConnected(true);
    }

    @Override
    public void onBluetoothDisconnected() {
        onNormalModeBluetooth();
    }

    @Override
    public void initAudioBluetooth() {

        onNormalModeBluetooth();

    }

    @Override
    public void onNormalModeBluetooth() {
        resetSco();
    }

    @Override
    public void onStartBluetoothSCO() {
        if(bluetoothAdapter.isEnabled() && audioManager != null){
            audioManager.startBluetoothSco();
        }
    }

}
