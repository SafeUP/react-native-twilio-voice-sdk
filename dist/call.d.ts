import AbstractCall, { nativeCallBase } from "./abstractCall";
declare type callState = "RINGING" | "CONNECTING" | "CONNECTED" | "RECONNECTING" | "DISCONNECTED";
export interface nativeCallObject extends nativeCallBase {
    state: callState;
    error?: {
        code?: number;
        domain?: string;
        message?: string;
        reason?: string;
    };
}
declare class Call extends AbstractCall {
    private _state;
    private _isMuted;
    private _onSpeaker;
    private constructor();
    readonly state: callState;
    readonly isMuted: boolean;
    readonly onSpeaker: boolean;
    disconnect: () => void;
    mute: (value: boolean) => void;
    setSpeakerPhone: (value: boolean) => void;
    sendDigits: (digits: string) => void;
    refresh: () => Promise<Call>;
    private updateFromNative;
}
export default Call;
