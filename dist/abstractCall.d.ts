export declare type nativeCallBase = {
    sid?: string;
    to?: string;
    from?: string;
};
declare abstract class AbstractCall {
    private _to;
    private _from;
    private _sid;
    readonly to: string | undefined;
    readonly from: string | undefined;
    readonly sid: string | undefined;
    protected updateFromNativeCallObject: (call: nativeCallBase) => void;
}
export default AbstractCall;
