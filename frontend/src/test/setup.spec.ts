import { describe, expect, it } from 'vitest'

describe('test transport guard', () => {
  it('blocks fetch until a test installs an explicit stub', async () => {
    await expect(fetch('/api/messages')).rejects.toThrow('fetch is blocked in tests')
  })

  it('blocks WebSocket until a test installs an explicit stub', () => {
    expect(() => new WebSocket('ws://localhost:4000/socket')).toThrow('WebSocket is blocked in tests')
  })
})
