import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'

const routes: RouteRecordRaw[] = []

export const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
})
