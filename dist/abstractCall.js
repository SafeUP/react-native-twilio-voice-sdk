class AbstractCall {
    constructor() {
        this.updateFromNativeCallObject = (call) => {
            if (call.sid !== undefined) {
                this._sid = call.sid;
            }
            if (call.from !== undefined) {
                this._from = call.from;
            }
            if (call.to !== undefined) {
                this._to = call.to;
            }
        };
    }
    get to() {
        return this._to;
    }
    get from() {
        return this._from;
    }
    get sid() {
        return this._sid;
    }
}
export default AbstractCall;
