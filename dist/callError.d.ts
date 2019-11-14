declare class CallError extends Error {
    readonly code: number | undefined;
    readonly reason: string | undefined;
    constructor(message?: string, reason?: string, code?: number);
}
export default CallError;
