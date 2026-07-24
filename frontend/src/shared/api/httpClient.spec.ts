import { afterEach, describe, expect, it, vi } from 'vitest'

import { requestJson } from './httpClient'

describe('httpClient', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('preserves AbortError so cancelled requests stay silent', async () => {
    const abortError = new DOMException('The operation was aborted', 'AbortError')
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(abortError))

    await expect(
      requestJson('/conversations/conversation-1/messages', {
        signal: new AbortController().signal,
        decode: (payload) => payload,
      }),
    ).rejects.toBe(abortError)
  })
})
