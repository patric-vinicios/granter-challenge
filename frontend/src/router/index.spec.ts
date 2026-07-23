import { createPinia } from 'pinia'
import { describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { createAppRouter } from './index'

describe('router auth guard', () => {
  it('redirects anonymous users from the inbox to login with a return path', async () => {
    const router = createAppRouter(createMemoryHistory(), createPinia())

    await router.push('/inbox')
    await router.isReady()

    expect(router.currentRoute.value.path).toBe('/')
    expect(router.currentRoute.value.query.redirect).toBe('/inbox')
  })

  it('keeps authenticated users on protected routes after bootstrap', async () => {
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
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(200, {
          user: {
            id: 'user-1',
            username: 'anabeatriz',
            name: 'Ana Beatriz',
            last_seen_at: null,
          },
        }),
      ),
    )

    const router = createAppRouter(createMemoryHistory(), createPinia())

    await router.push('/inbox')
    await router.isReady()

    expect(router.currentRoute.value.path).toBe('/inbox')
  })
})

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}
