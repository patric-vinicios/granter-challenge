import { createApp } from 'vue'

import App from './App.vue'
import { installTerminalAuthFailureHandler } from './app/installTerminalAuthFailureHandler'
import { pinia } from './app/pinia'
import { router } from './router'
import { useAuthStore } from './stores/auth.store'
import './style.css'

const authStore = useAuthStore(pinia)
installTerminalAuthFailureHandler(authStore, router)

createApp(App).use(pinia).use(router).mount('#app')
