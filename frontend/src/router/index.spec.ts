import { createPinia } from 'pinia'
import { describe, expect, it, vi } from 'vitest'
import { createMemoryHistory } from 'vue-router'

import { jsonResponse } from '@/test/http'

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

  it.each(['/','/cadastrar'])(
    'redirects authenticated users away from guest-only route %s',
    async (path) => {
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

      await router.push(path)
      await router.isReady()

      expect(router.currentRoute.value.path).toBe('/inbox')
    },
  )

  it('routes unknown paths to the not found screen instead of leaving the app blank', async () => {
    const router = createAppRouter(createMemoryHistory(), createPinia())

    await router.push('/rota-inexistente')
    await router.isReady()

    expect(router.currentRoute.value.name).toBe('not-found')
  })
})
