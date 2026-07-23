import { cleanup } from '@testing-library/vue'
import { afterEach, beforeEach, vi } from 'vitest'

const blockedTransportError = (transport: 'fetch' | 'WebSocket') =>
  new Error(`${transport} is blocked in tests; install an explicit test stub`)

beforeEach(() => {
  vi.stubGlobal(
    'fetch',
    vi.fn(() => Promise.reject(blockedTransportError('fetch'))),
  )

  class BlockedWebSocket {
    constructor() {
      throw blockedTransportError('WebSocket')
    }
  }

  vi.stubGlobal('WebSocket', BlockedWebSocket)
})

afterEach(() => {
  cleanup()
  window.localStorage.clear()
  vi.useRealTimers()
})
