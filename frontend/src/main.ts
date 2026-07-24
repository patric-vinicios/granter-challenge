import { createApp } from 'vue'

import App from './App.vue'
import { pinia } from './app/pinia'
import { router } from './router'
import { setTerminalAuthFailureHandler } from './shared/api/httpClient'
import { useAuthStore } from './stores/auth.store'
import './style.css'

const authStore = useAuthStore(pinia)
setTerminalAuthFailureHandler(() => {
  authStore.logout()
  void router.push({ name: 'login' })
})

createApp(App).use(pinia).use(router).mount('#app')
