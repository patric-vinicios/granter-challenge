import { render, type RenderResult } from '@testing-library/vue'
import { createPinia, type Pinia } from 'pinia'
import type { Component } from 'vue'
import { createMemoryHistory, createRouter, type Router, type RouteRecordRaw } from 'vue-router'

interface RenderWithAppOptions {
  routes: RouteRecordRaw[]
  initialRoute?: string
}

interface AppRenderResult extends RenderResult {
  pinia: Pinia
  router: Router
}

export async function renderWithApp(
  component: Component,
  { routes, initialRoute = '/' }: RenderWithAppOptions,
): Promise<AppRenderResult> {
  const pinia = createPinia()
  const router = createRouter({
    history: createMemoryHistory(),
    routes,
  })

  await router.push(initialRoute)
  await router.isReady()

  return {
    ...render(component, {
      global: {
        plugins: [pinia, router],
      },
    }),
    pinia,
    router,
  }
}
