import { beforeEach, describe, expect, it, vi, type Mock } from 'vitest'

interface PhoenixChannelRecord {
  join: Mock<() => unknown>
  leave: Mock<() => void>
  off: Mock<(event: string, ref: number) => void>
  on: Mock<(event: string, callback: (payload: unknown) => void) => number>
  push: Mock<(event: string, payload: Record<string, unknown>) => unknown>
  topic: string
  payload: Record<string, unknown>
}

interface PhoenixSocketRecord {
  channel: Mock<(topic: string, payload: Record<string, unknown>) => PhoenixChannelRecord>
  channels: PhoenixChannelRecord[]
  connect: Mock<() => void>
  disconnect: Mock<() => void>
  off: Mock<(refs: string[]) => void>
  onClose: Mock<(callback: () => void) => string>
  onError: Mock<(callback: (reason: unknown) => void) => string>
  onOpen: Mock<(callback: () => void) => string>
  options: { params: { token: string } }
  url: string
}

const phoenix = vi.hoisted(() => ({
  sockets: [] as PhoenixSocketRecord[],
}))

vi.mock('phoenix', () => ({
  Channel: class {},
  Socket: class {
    private record: PhoenixSocketRecord

    constructor(url: string, options: { params: { token: string } }) {
      const channels: PhoenixChannelRecord[] = []
      this.record = {
        url,
        options,
        channels,
        connect: vi.fn(),
        disconnect: vi.fn(),
        onOpen: vi.fn().mockReturnValue('open-ref'),
        onClose: vi.fn().mockReturnValue('close-ref'),
        onError: vi.fn().mockReturnValue('error-ref'),
        off: vi.fn(),
        channel: vi.fn((topic: string, payload: Record<string, unknown>) => {
          const push = { receive: vi.fn() }
          const channel = {
            topic,
            payload,
            join: vi.fn().mockReturnValue(push),
            leave: vi.fn(),
            on: vi.fn().mockReturnValue(42),
            off: vi.fn(),
            push: vi.fn().mockReturnValue(push),
          }
          channels.push(channel)
          return channel
        }),
      }
      phoenix.sockets.push(this.record)
    }

    connect() {
      return this.record.connect()
    }

    disconnect() {
      return this.record.disconnect()
    }

    onOpen(callback: () => void) {
      return this.record.onOpen(callback)
    }

    onClose(callback: () => void) {
      return this.record.onClose(callback)
    }

    onError(callback: (reason: unknown) => void) {
      return this.record.onError(callback)
    }

    off(refs: string[]) {
      return this.record.off(refs)
    }

    channel(topic: string, payload: Record<string, unknown>) {
      return this.record.channel(topic, payload)
    }
  },
}))

import { createRealtimeSocket } from './socket'

describe('createRealtimeSocket', () => {
  beforeEach(() => {
    phoenix.sockets.length = 0
  })

  it('configures and delegates the Phoenix socket lifecycle', () => {
    const socket = createRealtimeSocket('jwt-token')
    const record = requiredSocket()
    const onOpen = vi.fn()
    const onClose = vi.fn()
    const onError = vi.fn()

    expect(record.url).toBe('ws://localhost:4000/socket')
    expect(record.options).toEqual({ params: { token: 'jwt-token' } })

    socket.connect()
    expect(socket.onOpen(onOpen)).toBe('open-ref')
    expect(socket.onClose(onClose)).toBe('close-ref')
    expect(socket.onError(onError)).toBe('error-ref')
    socket.off('open-ref')
    socket.off(['close-ref', 'error-ref'])
    socket.disconnect()

    expect(record.connect).toHaveBeenCalledOnce()
    expect(record.onOpen).toHaveBeenCalledWith(onOpen)
    expect(record.onClose).toHaveBeenCalledWith(onClose)
    expect(record.onError).toHaveBeenCalledWith(onError)
    expect(record.off).toHaveBeenNthCalledWith(1, ['open-ref'])
    expect(record.off).toHaveBeenNthCalledWith(2, ['close-ref', 'error-ref'])
    expect(record.disconnect).toHaveBeenCalledOnce()
  })

  it('wraps channel operations without leaking the Phoenix implementation', () => {
    const socket = createRealtimeSocket('jwt-token')
    const channel = socket.channel('conversation:conversation-1', { cursor: 'next' })
    const record = requiredSocket()
    const channelRecord = record.channels[0]
    const handler = vi.fn()

    expect(record.channel).toHaveBeenCalledWith(
      'conversation:conversation-1',
      { cursor: 'next' },
    )
    expect(channel.join()).toBe(channelRecord?.join.mock.results[0]?.value)
    expect(channel.on('message:new', handler)).toBe(42)
    channel.off('message:new', 42)
    expect(channel.push('new_message', { body: 'Oi' })).toBe(
      channelRecord?.push.mock.results[0]?.value,
    )
    channel.leave()

    expect(channelRecord?.on).toHaveBeenCalledWith('message:new', handler)
    expect(channelRecord?.off).toHaveBeenCalledWith('message:new', 42)
    expect(channelRecord?.push).toHaveBeenCalledWith('new_message', { body: 'Oi' })
    expect(channelRecord?.leave).toHaveBeenCalledOnce()
  })

  it('uses an empty channel payload by default', () => {
    const socket = createRealtimeSocket('jwt-token')

    socket.channel('user:user-current')

    expect(requiredSocket().channel).toHaveBeenCalledWith('user:user-current', {})
  })
})

function requiredSocket(): PhoenixSocketRecord {
  const socket = phoenix.sockets[0]

  if (!socket) {
    throw new Error('Expected a Phoenix socket instance')
  }

  return socket
}
