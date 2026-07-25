import { createPinia, setActivePinia } from 'pinia'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'

import { requestJson, setTerminalAuthFailureHandler } from '@/shared/api/httpClient'
import { useAuthStore } from '@/stores/auth.store'
import { jsonResponse } from '@/test/http'

import { installTerminalAuthFailureHandler } from './installTerminalAuthFailureHandler'

describe('terminal authentication failure integration', () => {
  afterEach(() => setTerminalAuthFailureHandler(null))

  it('clears the session and redirects to login after an authenticated 401', async () => {
    const pinia = createPinia()
    setActivePinia(pinia)
    const auth = useAuthStore()
    auth.user = {
      id: 'user-current',
      username: 'patric',
      name: 'Patric',
      lastSeenAt: null,
    }
    auth.token = 'expired-token'
    auth.expiresAt = '2026-07-30T12:00:00Z'
    window.localStorage.setItem('granter.session', JSON.stringify(auth.$state))
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [
        { path: '/', name: 'login', component: { template: '<div>Login</div>' } },
        { path: '/inbox', name: 'inbox', component: { template: '<div>Inbox</div>' } },
      ],
    })
    await router.push('/inbox')
    installTerminalAuthFailureHandler(auth, router)
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
      requestJson('/contacts', {
        token: 'expired-token',
        decode: (payload) => payload,
      }),
    ).rejects.toMatchObject({ code: 'token_expired' })
    await vi.waitFor(() => expect(router.currentRoute.value.name).toBe('login'))

    expect(auth.isAuthenticated).toBe(false)
    expect(window.localStorage.getItem('granter.session')).toBeNull()
  })
})
