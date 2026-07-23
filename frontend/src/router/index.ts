import type { Pinia } from 'pinia'
import { createRouter, createWebHistory, type RouterHistory, type RouteRecordRaw } from 'vue-router'

import { pinia } from '@/app/pinia'
import { useAuthStore } from '@/stores/auth.store'

const routes: RouteRecordRaw[] = [
  {
    path: '/',
    name: 'login',
    component: () => import('@/views/LoginView.vue'),
    meta: { guestOnly: true },
  },
  {
    path: '/cadastrar',
    name: 'register',
    component: () => import('@/views/RegisterView.vue'),
    meta: { guestOnly: true },
  },
  {
    path: '/inbox',
    name: 'inbox',
    component: () => import('@/views/InboxView.vue'),
    meta: { requiresAuth: true },
  },
]

export function createAppRouter(history: RouterHistory, storePinia: Pinia = pinia) {
  const router = createRouter({ history, routes })

  router.beforeEach(async (to) => {
    const auth = useAuthStore(storePinia)

    await auth.bootstrap()

    if (to.meta.requiresAuth && !auth.isAuthenticated) {
      return {
        name: 'login',
        query: { redirect: to.fullPath },
      }
    }

    if (to.meta.guestOnly && auth.isAuthenticated) {
      return { name: 'inbox' }
    }

    return true
  })

  return router
}

export const router = createAppRouter(createWebHistory(import.meta.env.BASE_URL))
