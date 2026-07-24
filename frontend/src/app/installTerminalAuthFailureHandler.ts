import type { Router } from 'vue-router'

import { setTerminalAuthFailureHandler } from '@/shared/api/httpClient'
import type { useAuthStore } from '@/stores/auth.store'

type AuthStore = ReturnType<typeof useAuthStore>

export function installTerminalAuthFailureHandler(
  authStore: AuthStore,
  router: Router,
): void {
  setTerminalAuthFailureHandler(() => {
    authStore.logout()
    void router.push({ name: 'login' })
  })
}
