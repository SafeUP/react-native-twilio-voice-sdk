import AbstractCall from "./abstractCall";
class CancelledCallInvite extends AbstractCall {
    constructor(call) {
        super();
        this.updateFromNativeCallObject(call);
    }
}
export default CancelledCallInvite;
