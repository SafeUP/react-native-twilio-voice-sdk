var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : new P(function (resolve) { resolve(result.value); }).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
import { NativeEventEmitter, NativeModules, PermissionsAndroid } from 'react-native';
import Call from './call';
import CallError from "./callError";
const version = require('../package.json').version;
const RNTwilioVoice = NativeModules.RNTwilioVoiceSDK;
let twilioIdentity, twilioToken;
class TwilioVoice {
    constructor() {
        // private _registered: boolean = false
        this._currentCall = null;
        // private _currentInvite: CallInvite | null = null
        this._nativeAppEventEmitter = new NativeEventEmitter(RNTwilioVoice);
        this._internalEventHandlers = {};
        this._eventHandlers = {};
        this._isSetup = false;
        this._availableEvents = ["connect", "disconnect", "connectFailure", "reconnect", "reconnecting", "ringing"];
        this.connect = (params = {}) => {
            if (!this._isSetup) {
                return Promise.reject(new Error("Can't call connect on a destroyed Voice instance"));
            }
            if (this._currentCall !== null) {
                return Promise.reject(new Error("Can't call connect while a call is still going on"));
            }
            return new Promise((resolve, reject) => {
                RNTwilioVoice.connect(twilioToken, params).then((call) => {
                    this.createOrUpdateCall(call);
                    resolve(this._currentCall);
                }).catch((err) => reject(err));
            });
        };
        this.destroy = () => {
            this.disconnectAll();
            this._eventHandlers = {};
            this._isSetup = false;
            this.removeInternalCallEventHandlers();
        };
        this.removeListener = (event, handler) => () => {
            if (this._eventHandlers[event] === undefined) {
                return;
            } // no handlers for event
            const firstAppearance = this._eventHandlers[event].findIndex(fn => fn === handler);
            if (firstAppearance === -1) {
                return;
            } // handler doesn't exist
            this._eventHandlers[event].splice(firstAppearance, 1);
        };
        this.removeAllListeners = () => {
            for (let event in this._availableEvents) {
                this._eventHandlers[event] = undefined;
            }
        };
        this.getNativeVersion = () => {
            if (this._nativeVersion) {
                return Promise.resolve(this._nativeVersion);
            }
            return new Promise(resolve => RNTwilioVoice.getVersion()
                .then((v) => {
                this._nativeVersion = v;
                resolve(v);
            }));
        };
        this.setup = () => {
            this.addInternalCallEventHandlers();
            this._isSetup = true;
        };
        this.addInternalCallEventHandlers = () => {
            const handlers = {
                "connect": this.onConnect,
                "disconnect": this.onDisconnect,
                "connectFailure": this.onConnectFailure,
                "reconnect": this.onReconnect,
                "reconnecting": this.onReconnecting,
                "ringing": this.onRinging
            };
            let event;
            for (event in handlers) {
                if (this._internalEventHandlers[event] === undefined) {
                    this._internalEventHandlers[event] = this._nativeAppEventEmitter.addListener(event, handlers[event]);
                }
            }
        };
        this.removeInternalCallEventHandlers = () => {
            const callEvents = new Set(["connect", "disconnect", "connectFailure", "reconnect", "reconnecting", "ringing"]);
            let event;
            for (event of callEvents) {
                if (this._internalEventHandlers[event] !== undefined) {
                    this._internalEventHandlers[event].remove();
                    delete this._internalEventHandlers[event];
                }
            }
        };
        this.handleEvent = (eventName, ...args) => {
            if (this._eventHandlers[eventName] === undefined) {
                return;
            }
            let handler;
            for (handler of this._eventHandlers[eventName]) {
                // @ts-ignore too much meta-programming for typescript
                handler(...args);
            }
        };
        this.createOrUpdateCall = (nativeCallObject) => {
            if (this._currentCall === null) {
                // @ts-ignore we're calling the private constructor on purpose
                // the constructor is private to hide it from Intellisense
                this._currentCall = new Call(nativeCallObject);
            }
            else {
                // @ts-ignore we're calling the protected method on purpose
                // that method is protected to hide it from Intellisense
                this._currentCall.updateFromNative(nativeCallObject);
            }
        };
        this.createCallError = (nativeCallObject) => {
            if (nativeCallObject.error !== undefined) {
                const { message, code, reason } = nativeCallObject.error;
                return new CallError(message, reason, code);
            }
            return;
        };
        this.parseNativeCallObject = (nativeCallObject) => {
            this.createOrUpdateCall(nativeCallObject);
            return this.createCallError(nativeCallObject);
        };
        this.onConnect = (nativeCallObject) => {
            this.parseNativeCallObject(nativeCallObject);
            this.handleEvent("connect", this._currentCall);
        };
        this.onDisconnect = (nativeCallObject) => {
            const error = this.parseNativeCallObject(nativeCallObject);
            this.handleEvent("disconnect", this._currentCall, error);
            // After disconnect the current call is null
            this._currentCall = null;
        };
        this.onConnectFailure = (nativeCallObject) => {
            const error = this.parseNativeCallObject(nativeCallObject);
            this.handleEvent("connectFailure", this._currentCall, error);
            // After connect failure the current call is null
            this._currentCall = null;
        };
        this.onReconnect = (nativeCallObject) => {
            this.parseNativeCallObject(nativeCallObject);
            this.handleEvent("reconnect", this._currentCall);
        };
        this.onReconnecting = (nativeCallObject) => {
            const error = this.parseNativeCallObject(nativeCallObject);
            this.handleEvent("reconnecting", this._currentCall, error);
        };
        this.onRinging = (nativeCallObject) => {
            this.parseNativeCallObject(nativeCallObject);
            this.handleEvent("ringing", this._currentCall);
        };
        this.requestCameraPermission = () => __awaiter(this, void 0, void 0, function* () {
            try {
                const granted = yield PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO, {
                    title: 'SafeUP',
                    message: 'SafeUP App needs access to your microphone to make calls',
                    buttonNeutral: 'Ask Me Later',
                    buttonNegative: 'Cancel',
                    buttonPositive: 'OK',
                });
                if (granted === PermissionsAndroid.RESULTS.GRANTED) {
                    console.log('You can use the camera');
                }
                else {
                    console.log('Camera permission denied');
                }
                return granted;
            }
            catch (err) {
                console.warn(err);
                return false;
            }
        });
        this.setup();
        this.on.bind(this);
        this.getNativeVersion().then();
    }
    get version() {
        return version;
    }
    get nativeVersion() {
        return this._nativeVersion;
    }
    get status() {
        if (this._currentCall !== null) {
            return "BUSY";
        }
        // if(this._registered) {
        //   return "READY"
        // }
        return "OFFLINE";
    }
    setIdentity(identity) {
        twilioIdentity = identity;
        twilioIdentity = twilioIdentity;
    }
    setToken(token) {
        twilioToken = token;
    }
    get availableEvents() {
        return this._availableEvents;
    }
    // on(event: "incoming", handler: callInviteHandler): removeEventHandler;
    // on(event: "cancel", handler: callInviteCancelHandler): removeEventHandler;
    // on(event: registrationEvent, handler: registrationEventHandler):removeEventHandler
    on(event, handler) {
        if (this._eventHandlers[event] === undefined) {
            this._eventHandlers[event] = [];
        }
        this._eventHandlers[event].push(handler);
        return this.removeListener(event, handler);
    }
    disconnectAll() {
        // if(this._registered) { this.unregister() }
        // if(this._currentInvite !== null) {
        //   this._currentInvite.reject()
        //   this._currentInvite = null
        // }
        if (this._currentCall !== null) {
            this._currentCall.disconnect();
            this._currentCall = null;
        }
    }
}
export default new TwilioVoice();
