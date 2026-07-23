import { Channel, Socket } from 'phoenix'

import { getSocketUrl } from '@/shared/config/apiConfig'

export interface RealtimePush {
  receive(status: 'ok' | 'error', callback: (payload: unknown) => void): RealtimePush
}

export interface RealtimeChannel {
  join(): RealtimePush
  leave(): void
  on(event: string, callback: (payload: unknown) => void): number
  off(event: string, ref: number): void
  push(event: string, payload: Record<string, unknown>): RealtimePush
}

export interface RealtimeSocket {
  connect(): void
  disconnect(): void
  channel(topic: string, payload?: Record<string, unknown>): RealtimeChannel
}

export type RealtimeSocketFactory = (token: string) => RealtimeSocket

export const createRealtimeSocket: RealtimeSocketFactory = (token: string) => {
  const socket = new Socket(getSocketUrl(), { params: { token } })

  return {
    connect: () => socket.connect(),
    disconnect: () => socket.disconnect(),
    channel: (topic, payload = {}) => wrapChannel(socket.channel(topic, payload)),
  }
}

function wrapChannel(channel: Channel): RealtimeChannel {
  return {
    join: () => channel.join(),
    leave: () => {
      channel.leave()
    },
    on: (event, callback) => channel.on(event, callback),
    off: (event, ref) => channel.off(event, ref),
    push: (event, payload) => channel.push(event, payload),
  }
}
