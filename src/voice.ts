import {EmitterSubscription, NativeEventEmitter, NativeModules, PermissionsAndroid } from 'react-native'

import Call, {nativeCallObject} from './call'
import CallInvite from "./callInvite"
import CancelledCallInvite from "./cancelledCallInvite"
import CallError from "./callError"

const version = require('../package.json').version

const RNTwilioVoice = NativeModules.RNTwilioVoiceSDK

type voiceStatus = "READY" | "OFFLINE" | "BUSY"

type registrationEvent = "ready" | "offline"
type inviteEvent = "incoming" | "cancel"
type callEventWithoutError = "connect" | "reconnect" | "ringing"
type callEventWithError = "connectFailure" | "reconnecting" | "disconnect"
type callEvent = callEventWithoutError | callEventWithError
type voiceEvent = registrationEvent | inviteEvent | callEvent

type callEventHandler = (call: Call) => void
type callEventWithErrorHandler = (call: Call, err?: CallError) => void
type callInviteHandler = (invite: CallInvite) => void
type callInviteCancelHandler = (canceledInvite: CancelledCallInvite) => void
type registrationEventHandler = (err?: Error) => void
type handlerFn = callEventHandler | callInviteHandler | callInviteCancelHandler | registrationEventHandler
type voiceEventHandlers = Partial<{
    [key in voiceEvent]: Array<handlerFn>
}>
type internalCallEventHandlers = Partial<{
  [key in callEvent]: EmitterSubscription | null
}>
type internalInviteEventHandlers = Partial<{
  [key in inviteEvent]: EmitterSubscription | null
}>
type internalVoiceEventHandlers = internalCallEventHandlers & internalInviteEventHandlers

type removeHandlerFn = () => void

let twilioIdentity: String, twilioToken: String

class TwilioVoice {
  // private _registered: boolean = false
  private _currentCall: Call | null = null
  // private _currentInvite: CallInvite | null = null
  private _nativeAppEventEmitter = new NativeEventEmitter(RNTwilioVoice)
  private _internalEventHandlers: internalVoiceEventHandlers = {}
  private _eventHandlers: voiceEventHandlers = {}
  private _isSetup: boolean = false
  private _nativeVersion: string | undefined

  private _availableEvents: Array<voiceEvent> = ["connect", "disconnect", "connectFailure", "reconnect", "reconnecting", "ringing"]

  public constructor () {
    this.setup()
    this.on.bind(this)
    this.getNativeVersion().then()
  }

  public get version(): string {
      return version
  }

  public get nativeVersion(): string | undefined {
    return this._nativeVersion
  }

  public get status(): voiceStatus {
    if(this._currentCall !== null) {
      return "BUSY"
    }
    // if(this._registered) {
    //   return "READY"
    // }
    return "OFFLINE"
  }

  public setIdentity(identity: String) {
    twilioIdentity = identity
    twilioIdentity = twilioIdentity
  }

  public setToken(token: String) {
    twilioToken = token
  }

  public get availableEvents(): Array<voiceEvent> {
    return this._availableEvents;
  }

  public connect = (accessToken: string, params = {}): Promise<Call> => {
    if(!this._isSetup) {
      return Promise.reject(new Error("Can't call connect on a destroyed Voice instance"));
    }
    if(this._currentCall !== null) {
      return Promise.reject(new Error("Can't call connect while a call is still going on"));
    }
    return new Promise((resolve, reject) => {
      RNTwilioVoice.connect(accessToken, params).then((call: Call) => {
        this.createOrUpdateCall(call)
        resolve(this._currentCall as Call)
      }).catch((err: any) => reject(err))
    })
  }

  public destroy = () => {
    this.disconnectAll()
    this._eventHandlers = {}
    this._isSetup = false
    this.removeInternalCallEventHandlers()
  }

  // // TODO: Implement this
  // public register = (): void => {
  //   if(!this._isSetup) {
  //     throw new Error("Can't call connect without calling setup first")
  //   }
  //   this._registered = true
  // }
  //
  // // TODO: Implement this
  // public unregister = (): void => {
  //   if(!this._registered) {
  //     return // Calling unregister without being registered first
  //   }
  //   this._registered = false
  // }

  on(event: "connect", handler: callEventHandler): removeHandlerFn;
  on(event: "reconnect", handler: callEventHandler): removeHandlerFn;
  on(event: "ringing", handler: callEventHandler): removeHandlerFn;
  on(event: "connectFailure", handler: callEventWithErrorHandler): removeHandlerFn;
  on(event: "reconnecting", handler: callEventWithErrorHandler): removeHandlerFn;
  on(event: "disconnect", handler: callEventWithErrorHandler): removeHandlerFn;
  // on(event: "incoming", handler: callInviteHandler): removeEventHandler;
  // on(event: "cancel", handler: callInviteCancelHandler): removeEventHandler;
  // on(event: registrationEvent, handler: registrationEventHandler):removeEventHandler
  public on(event: voiceEvent, handler: handlerFn) {
    if(this._eventHandlers[event] === undefined) {
      this._eventHandlers[event] = []
    }
    this._eventHandlers[event]!.push(handler)
    return this.removeListener(event, handler)
  }

  private removeListener = (event: voiceEvent, handler: handlerFn) => () => {
    if(this._eventHandlers[event] === undefined) { return } // no handlers for event
    const firstAppearance = this._eventHandlers[event]!.findIndex(fn => fn === handler)
    if(firstAppearance === -1) { return } // handler doesn't exist
    this._eventHandlers[event]!.splice(firstAppearance, 1)
  }

  public removeAllListeners = () => {
    for (let event in this._availableEvents) {
      this._eventHandlers[event as voiceEvent] = undefined
    }
  }

  private getNativeVersion = (): Promise<string> => {
    if(this._nativeVersion) {
      return Promise.resolve(this._nativeVersion)
    }
    return new Promise<string>(resolve =>
      RNTwilioVoice.getVersion()
        .then((v: string) => {
          this._nativeVersion = v
          resolve(v)
        })
    )
  }

  private setup = () => {
    this.addInternalCallEventHandlers()
    this._isSetup = true
  }

  private addInternalCallEventHandlers = () => {
    const handlers: { [key in callEvent]: handlerFn} = {
      "connect": this.onConnect,
      "disconnect": this.onDisconnect,
      "connectFailure": this.onConnectFailure,
      "reconnect": this.onReconnect,
      "reconnecting": this.onReconnecting,
      "ringing": this.onRinging
    }
    let event: callEvent
    for (event in handlers) {
      if(this._internalEventHandlers[event] === undefined) {
        this._internalEventHandlers[event] = this._nativeAppEventEmitter.addListener(event, handlers[event])
      }
    }
  }

  private removeInternalCallEventHandlers = () => {
    const callEvents: Set<callEvent> = new Set(["connect", "disconnect", "connectFailure", "reconnect", "reconnecting", "ringing"])
    let event: callEvent
    for(event of callEvents) {
      if(this._internalEventHandlers[event] !== undefined) {
        this._internalEventHandlers[event]!.remove()
        delete this._internalEventHandlers[event]
      }
    }
  }

  private handleEvent = (eventName: voiceEvent, ...args: any[]) => {
    if(this._eventHandlers[eventName] === undefined) {
      return
    }
    let handler: handlerFn
    for(handler of this._eventHandlers[eventName]!) {
      // @ts-ignore too much meta-programming for typescript
      handler(...args)
    }
  }

  private createOrUpdateCall = (nativeCallObject: nativeCallObject) => {
    if(this._currentCall === null) {
      // @ts-ignore we're calling the private constructor on purpose
      // the constructor is private to hide it from Intellisense
      this._currentCall = new Call(nativeCallObject)
    } else {
      // @ts-ignore we're calling the protected method on purpose
      // that method is protected to hide it from Intellisense
      this._currentCall.updateFromNative(nativeCallObject)
    }
  }

  private createCallError = (nativeCallObject: nativeCallObject): Error | undefined => {
    if(nativeCallObject.error !== undefined) {
      const { message, code, reason } = nativeCallObject.error
      return new CallError(message, reason, code)
    }
    return
  }

  private parseNativeCallObject = (nativeCallObject: nativeCallObject): Error | undefined => {
    this.createOrUpdateCall(nativeCallObject)
    return this.createCallError(nativeCallObject)
  }

  private onConnect = (nativeCallObject: nativeCallObject) => {
    this.parseNativeCallObject(nativeCallObject)
    this.handleEvent("connect", this._currentCall)
  }

  private onDisconnect = (nativeCallObject: nativeCallObject) => {
    const error = this.parseNativeCallObject(nativeCallObject)
    this.handleEvent("disconnect", this._currentCall, error)
    // After disconnect the current call is null
    this._currentCall = null
  }

  private onConnectFailure = (nativeCallObject: nativeCallObject) => {
    const error = this.parseNativeCallObject(nativeCallObject)
    this.handleEvent("connectFailure", this._currentCall, error)
    // After connect failure the current call is null
    this._currentCall = null
  }

  private onReconnect = (nativeCallObject: nativeCallObject) => {
    this.parseNativeCallObject(nativeCallObject)
    this.handleEvent("reconnect", this._currentCall)
  }

  private onReconnecting = (nativeCallObject: nativeCallObject) => {
    const error = this.parseNativeCallObject(nativeCallObject)
    this.handleEvent("reconnecting", this._currentCall, error)
  }

  private onRinging = (nativeCallObject: nativeCallObject) => {
    this.parseNativeCallObject(nativeCallObject)
    this.handleEvent("ringing", this._currentCall)
  }

  private disconnectAll() {
    // if(this._registered) { this.unregister() }
    // if(this._currentInvite !== null) {
    //   this._currentInvite.reject()
    //   this._currentInvite = null
    // }
    if(this._currentCall !== null) {
      this._currentCall.disconnect()
      this._currentCall = null
    }
  }

  public requestCameraPermission = async () => {
    try {
      const granted = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        {
          title: 'SafeUP',
          message:
            'SafeUP App needs access to your microphone to make calls',
          buttonNeutral: 'Ask Me Later',
          buttonNegative: 'Cancel',
          buttonPositive: 'OK',
        },
      )
      if (granted === PermissionsAndroid.RESULTS.GRANTED) {
        console.log('You can use the camera')
      } else {
        console.log('Camera permission denied')
      }
      return granted
    } catch (err) {
      console.warn(err)
      return false
    }
  }

}

export default new TwilioVoice()
