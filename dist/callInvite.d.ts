import AbstractCall from "./abstractCall";
declare type customParams = {
    [key: string]: string;
};
declare class CallInvite extends AbstractCall {
    private readonly _customParameters;
    private constructor();
    readonly customParameters: customParams;
    accept(): void;
    reject(): void;
}
export default CallInvite;
