import { NativeModules } from 'react-native';
import AbstractCall from "./abstractCall";
const TwilioVoice = NativeModules.RNTwilioVoiceSDK;
class Call extends AbstractCall {
    // The constructor is meant to be called only from the Device class
    // when making a connect, or receiving an incoming
    constructor(call) {
        super();
        this._isMuted = false;
        this._onSpeaker = false;
        this.disconnect = () => {
            TwilioVoice.disconnect();
        };
        this.mute = (value) => {
            TwilioVoice.setMuted(value);
            this._isMuted = value;
        };
        this.setSpeakerPhone = (value) => {
            TwilioVoice.setSpeakerPhone(value);
            this._onSpeaker = value;
        };
        this.sendDigits = (digits) => {
            TwilioVoice.sendDigits(digits);
        };
        this.refresh = () => {
            return TwilioVoice.getActiveCall()
                .then((call) => {
                this.updateFromNative(call);
                return Promise.resolve(this);
            }).catch((err) => {
                // err should be that there is no call, therefore
                // the status is set to DISCONNECTED
                console.log(err.message);
                this._state = "DISCONNECTED";
                return Promise.resolve(this);
            });
        };
        this.updateFromNative = (call) => {
            this.updateFromNativeCallObject(call);
            this._state = call.state;
        };
        this.updateFromNative(call);
    }
    get state() {
        return this._state;
    }
    get isMuted() {
        return this._isMuted;
    }
    get onSpeaker() {
        return this._onSpeaker;
    }
}
export default Call;
