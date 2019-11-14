import AbstractCall from "./abstractCall";
class CallInvite extends AbstractCall {
    constructor(callInvite) {
        super();
        this._customParameters = {};
        this.updateFromNativeCallObject(callInvite);
        if (callInvite.customParameters !== undefined) {
            this._customParameters = Object.assign({}, this._customParameters, callInvite.customParameters);
        }
    }
    get customParameters() {
        return this._customParameters;
    }
    // TODO: accept should take an options object
    accept() {
    }
    reject() {
    }
}
export default CallInvite;
