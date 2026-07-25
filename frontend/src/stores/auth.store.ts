import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

import {
  getCurrentUser,
  login as loginRequest,
  logout as logoutRequest,
  register as registerRequest,
} from '@/features/auth/auth.api'
import { clearSession, readSession, writeSession } from '@/features/auth/auth.storage'
import { type AuthSession, type AuthUser, type LoginRequest, type RegisterRequest } from '@/features/auth/auth.contracts'
import { isApiError } from '@/shared/api/errors'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<AuthUser | null>(null)
  const token = ref<string | null>(null)
  const expiresAt = ref<string | null>(null)
  const isBootstrapping = ref(false)
  const didBootstrap = ref(false)

  const isAuthenticated = computed(() => token.value !== null && user.value !== null)

  function hydrate(session: AuthSession): void {
    user.value = session.user
    token.value = session.token
    expiresAt.value = session.expiresAt
  }

  async function bootstrap(): Promise<void> {
    if (didBootstrap.value || isBootstrapping.value) {
      return
    }

    const storedSession = readSession()

    if (!storedSession) {
      didBootstrap.value = true
      return
    }

    hydrate(storedSession)
    isBootstrapping.value = true

    try {
      user.value = await getCurrentUser(storedSession.token)
      writeSession({
        user: user.value,
        token: storedSession.token,
        expiresAt: storedSession.expiresAt,
      })
    } catch (error) {
      if (isApiError(error) && (error.code === 'token_expired' || error.code === 'unauthenticated')) {
        logout()
      } else {
        hydrate(storedSession)
      }
    } finally {
      isBootstrapping.value = false
      didBootstrap.value = true
    }
  }

  async function login(credentials: LoginRequest): Promise<void> {
    setSession(await loginRequest(credentials))
  }

  async function register(account: RegisterRequest): Promise<void> {
    setSession(await registerRequest(account))
  }

  function setSession(session: AuthSession): void {
    hydrate(session)
    writeSession(session)
    didBootstrap.value = true
  }

  function logout(options: { revoke?: boolean } = {}): void {
    const currentToken = token.value

    // Revoke the token server-side only on a user-initiated logout; the forced
    // paths (expired/invalid token) already hold a token the server rejects.
    if (options.revoke && currentToken) {
      void logoutRequest(currentToken).catch(() => {})
    }

    user.value = null
    token.value = null
    expiresAt.value = null
    clearSession()
    didBootstrap.value = true
  }

  return {
    user,
    token,
    expiresAt,
    isBootstrapping,
    didBootstrap,
    isAuthenticated,
    bootstrap,
    login,
    register,
    logout,
  }
})
