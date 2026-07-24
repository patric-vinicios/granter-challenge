import { afterEach, describe, expect, it, vi } from 'vitest'

import { requestJson, setTerminalAuthFailureHandler } from './httpClient'

describe('httpClient', () => {
  afterEach(() => {
    setTerminalAuthFailureHandler(null)
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

  it('calls the terminal auth failure handler for authenticated expired sessions', async () => {
    const handler = vi.fn()
    setTerminalAuthFailureHandler(handler)
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(401, {
          errors: {
            code: 'token_expired',
            detail: 'Your session has expired, please log in again',
          },
        }),
      ),
    )

    await expect(
      requestJson('/auth/me', {
        token: 'expired-token',
        decode: (payload) => payload,
      }),
    ).rejects.toMatchObject({ status: 401 })

    expect(handler).toHaveBeenCalledOnce()
  })

  it('does not call the terminal auth failure handler for anonymous unauthorized responses', async () => {
    const handler = vi.fn()
    setTerminalAuthFailureHandler(handler)
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(401, {
          errors: {
            code: 'unauthenticated',
            detail: 'You need to sign in',
          },
        }),
      ),
    )

    await expect(
      requestJson('/auth/login', {
        decode: (payload) => payload,
      }),
    ).rejects.toMatchObject({ status: 401 })

    expect(handler).not.toHaveBeenCalled()
  })
})

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
