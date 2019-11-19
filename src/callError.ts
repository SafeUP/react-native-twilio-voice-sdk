class CallError extends Error {
  public readonly code: number | undefined
  public readonly reason: string | undefined
  constructor(message?: string, reason?: string, code?: number) {
    super(message)
    // See: https://stackoverflow.com/questions/41102060/typescript-extending-error-class
    Object.setPrototypeOf(this, CallError.prototype)
    this.code = code
    this.reason = reason
  }
}

export default CallError
