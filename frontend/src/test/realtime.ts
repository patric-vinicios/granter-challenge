import type {
  RealtimeChannel,
  RealtimePush,
  RealtimeSocket,
} from '@/shared/realtime/socket'

type PushStatus = 'ok' | 'error'
type SocketState = 'open' | 'close' | 'error'

export class FakePush implements RealtimePush {
  private callbacks: Partial<Record<PushStatus, (payload: unknown) => void>> = {}

  receive(status: PushStatus, callback: (payload: unknown) => void): FakePush {
    this.callbacks[status] = callback
    return this
  }

  reply(status: PushStatus, payload: unknown): void {
    this.callbacks[status]?.(payload)
  }
}

export class FakeChannel implements RealtimeChannel {
  handlers = new Map<string, Array<(payload: unknown) => void>>()
  joinPush = new FakePush()
  lastPush: { event: string; payload: Record<string, unknown>; push: FakePush } | null = null
  leaveCount = 0
  offEvents: string[] = []

  join(): FakePush {
    return this.joinPush
  }

  replyJoin(status: PushStatus, payload: unknown = {}): void {
    this.joinPush.reply(status, payload)
  }

  okJoin(): void {
    this.replyJoin('ok')
  }

  leave(): void {
    this.leaveCount += 1
  }

  on(event: string, callback: (payload: unknown) => void): number {
    const callbacks = this.handlers.get(event) ?? []
    callbacks.push(callback)
    this.handlers.set(event, callbacks)
    return callbacks.length
  }

  off(event: string): void {
    this.offEvents.push(event)
  }

  push(event: string, payload: Record<string, unknown>): FakePush {
    const push = new FakePush()
    this.lastPush = { event, payload, push }
    return push
  }

  replyLastPush(status: PushStatus, payload: unknown): void {
    this.lastPush?.push.reply(status, payload)
  }

  pushServer(event: string, payload: unknown): void {
    for (const callback of this.handlers.get(event) ?? []) {
      callback(payload)
    }
  }
}

export class FakeSocket implements RealtimeSocket {
  connected = false
  disconnected = false
  channels = new Map<string, FakeChannel>()
  readonly offRefs: string[] = []
  readonly token: string
  private nextStateRef = 0
  private stateCallbacks = new Map<string, { state: SocketState; callback: () => void }>()

  constructor(token: string) {
    this.token = token
  }

  get stateCallbackCount(): number {
    return this.stateCallbacks.size
  }

  connect(): void {
    this.connected = true
  }

  disconnect(): void {
    this.disconnected = true
  }

  onOpen(callback: () => void): string {
    return this.registerStateCallback('open', callback)
  }

  onClose(callback: () => void): string {
    return this.registerStateCallback('close', callback)
  }

  onError(callback: (reason: unknown) => void): string {
    return this.registerStateCallback('error', () => callback(new Error('socket error')))
  }

  off(refs: string | string[]): void {
    const normalizedRefs = Array.isArray(refs) ? refs : [refs]

    for (const ref of normalizedRefs) {
      this.offRefs.push(ref)
      this.stateCallbacks.delete(ref)
    }
  }

  channel(topic: string): FakeChannel {
    const existing = this.channels.get(topic)

    if (existing) {
      return existing
    }

    const channel = new FakeChannel()
    this.channels.set(topic, channel)
    return channel
  }

  channelFor(topic: string): FakeChannel {
    const channel = this.channels.get(topic)

    if (!channel) {
      throw new Error(`Missing channel ${topic}`)
    }

    return channel
  }

  emitOpen(): void {
    this.emitState('open')
  }

  emitClose(): void {
    this.emitState('close')
  }

  emitError(): void {
    this.emitState('error')
  }

  private emitState(state: SocketState): void {
    for (const entry of this.stateCallbacks.values()) {
      if (entry.state === state) {
        entry.callback()
      }
    }
  }

  private registerStateCallback(state: SocketState, callback: () => void): string {
    const ref = `socket-ref-${++this.nextStateRef}`
    this.stateCallbacks.set(ref, { state, callback })
    return ref
  }
}
