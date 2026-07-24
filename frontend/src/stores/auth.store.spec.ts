import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { useAuthStore } from './auth.store'

describe('auth store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('bootstraps a stored session through /auth/me', async () => {
    window.localStorage.setItem(
      'granter.session',
      JSON.stringify({
        user: {
          id: 'user-1',
          username: 'anabeatriz',
          name: 'Ana Beatriz',
          lastSeenAt: null,
        },
        token: 'jwt-token',
        expiresAt: '2026-07-30T12:00:00Z',
      }),
    )
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse(200, {
        user: {
          id: 'user-1',
          username: 'anabeatriz',
          name: 'Ana Beatriz Atualizada',
          last_seen_at: null,
        },
      }),
    )
    vi.stubGlobal('fetch', fetchMock)

    const auth = useAuthStore()
    await auth.bootstrap()

    expect(auth.isAuthenticated).toBe(true)
    expect(auth.user?.name).toBe('Ana Beatriz Atualizada')
    expect(fetchMock).toHaveBeenCalledWith(
      'http://localhost:4000/api/auth/me',
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: 'Bearer jwt-token',
        }),
      }),
    )
  })

  it('clears an expired stored session during bootstrap', async () => {
    window.localStorage.setItem(
      'granter.session',
      JSON.stringify({
        user: {
          id: 'user-1',
          username: 'anabeatriz',
          name: 'Ana Beatriz',
          lastSeenAt: null,
        },
        token: 'expired-token',
        expiresAt: '2026-07-30T12:00:00Z',
      }),
    )
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

    const auth = useAuthStore()
    await auth.bootstrap()

    expect(auth.isAuthenticated).toBe(false)
    expect(window.localStorage.getItem('granter.session')).toBeNull()
  })

  it('exposes the complete bootstrap lifecycle through Pinia state', () => {
    const auth = useAuthStore()

    expect(auth.$state).toHaveProperty('didBootstrap')
  })
})

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
