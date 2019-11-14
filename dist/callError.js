class CallError extends Error {
    constructor(message, reason, code) {
        super(message);
        // See: https://stackoverflow.com/questions/41102060/typescript-extending-error-class
        Object.setPrototypeOf(this, new.target.prototype);
        this.code = code;
        this.reason = reason;
    }
}
export default CallError;
