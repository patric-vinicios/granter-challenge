<template>
  <AuthLayout>
    <form class="grid gap-4" @submit.prevent="submit">
      <div class="grid gap-2">
        <label class="sr-only" for="username">Usuario</label>
        <input
          id="username"
          v-model.trim="username"
          class="h-9 w-full rounded-lg border border-[#e8e8e8] bg-white px-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          autocomplete="username"
          placeholder="Usuario (Ex.: anabeatriz)"
          type="text"
        />
      </div>

      <div class="grid gap-2">
        <label class="sr-only" for="password">Senha</label>
        <div class="relative">
          <input
            id="password"
            v-model="password"
            class="h-9 w-full rounded-lg border border-[#e8e8e8] bg-white px-3 pr-11 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
            :type="showPassword ? 'text' : 'password'"
            autocomplete="current-password"
            placeholder="Senha"
          />
          <button
            class="absolute right-0 top-0 grid h-9 w-9 place-items-center rounded-lg text-[#171717] hover:bg-[#f5f5f5]"
            :aria-label="showPassword ? 'Ocultar senha' : 'Mostrar senha'"
            type="button"
            @click="showPassword = !showPassword"
          >
            <EyeOff v-if="showPassword" :size="17" :stroke-width="2" aria-hidden="true" />
            <Eye v-else :size="17" :stroke-width="2" aria-hidden="true" />
          </button>
        </div>
      </div>

      <button
        class="inline-flex min-h-9 items-center justify-center rounded-lg border border-black bg-black px-3.5 text-[13px] font-bold text-white hover:bg-[#222222]"
        type="submit"
      >
        Entrar
      </button>
    </form>

    <p class="m-0 text-[13px] text-[#737373]">
      Ainda nao tem conta?
      <RouterLink class="font-bold text-[#171717] no-underline hover:underline" to="/cadastrar">
        Cadastrar
      </RouterLink>
    </p>
  </AuthLayout>
</template>

<script setup lang="ts">
import { Eye, EyeOff } from '@lucide/vue'
import { ref } from 'vue'
import { useRouter } from 'vue-router'

import AuthLayout from '@/layouts/AuthLayout.vue'

const username = ref('')
const password = ref('')
const showPassword = ref(false)
const router = useRouter()

function submit() {
  router.push('/inbox')
}
</script>
