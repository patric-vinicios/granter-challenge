<template>
  <AuthLayout>
    <form class="grid gap-4" novalidate @submit.prevent="submit">
      <div class="grid gap-2">
        <label class="sr-only" for="name">Nome</label>
        <input
          id="name"
          v-model.trim="name"
          class="h-9 w-full rounded-lg border border-[#e8e8e8] bg-white px-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          autocomplete="name"
          :aria-invalid="Boolean(fieldError('name'))"
          :aria-describedby="fieldError('name') ? 'name-error' : undefined"
          :disabled="isSubmitting"
          placeholder="Nome (Ex.: Ana Beatriz)"
          type="text"
        />
        <p v-if="fieldError('name')" id="name-error" class="m-0 text-[12px] text-[#b91c1c]">
          {{ fieldError('name') }}
        </p>
      </div>

      <div class="grid gap-2">
        <label class="sr-only" for="username">Usuario</label>
        <input
          id="username"
          v-model.trim="username"
          class="h-9 w-full rounded-lg border border-[#e8e8e8] bg-white px-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          autocomplete="username"
          :aria-invalid="Boolean(fieldError('username'))"
          :aria-describedby="fieldError('username') ? 'username-error' : undefined"
          :disabled="isSubmitting"
          placeholder="Usuario (Ex.: anabeatriz)"
          type="text"
        />
        <p v-if="fieldError('username')" id="username-error" class="m-0 text-[12px] text-[#b91c1c]">
          {{ fieldError('username') }}
        </p>
      </div>

      <div class="grid gap-2">
        <label class="sr-only" for="password">Senha</label>
        <div class="relative">
          <input
            id="password"
            v-model="password"
            class="h-9 w-full rounded-lg border border-[#e8e8e8] bg-white px-3 pr-11 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
            :type="showPassword ? 'text' : 'password'"
            autocomplete="new-password"
            :aria-invalid="Boolean(fieldError('password'))"
            :aria-describedby="fieldError('password') ? 'password-error' : undefined"
            :disabled="isSubmitting"
            placeholder="Senha"
          />
          <button
            class="absolute right-0 top-0 grid h-9 w-9 place-items-center rounded-lg text-[#171717] hover:bg-[#f5f5f5]"
            :aria-label="showPassword ? 'Ocultar senha' : 'Mostrar senha'"
            :disabled="isSubmitting"
            type="button"
            @click="showPassword = !showPassword"
          >
            <EyeOff v-if="showPassword" :size="17" :stroke-width="2" aria-hidden="true" />
            <Eye v-else :size="17" :stroke-width="2" aria-hidden="true" />
          </button>
        </div>
        <p v-if="fieldError('password')" id="password-error" class="m-0 text-[12px] text-[#b91c1c]">
          {{ fieldError('password') }}
        </p>
      </div>

      <p v-if="formError" class="m-0 text-[13px] text-[#b91c1c]" role="alert">
        {{ formError }}
      </p>

      <button
        class="inline-flex min-h-9 items-center justify-center rounded-lg border border-black bg-black px-3.5 text-[13px] font-bold text-white hover:bg-[#222222] disabled:cursor-not-allowed disabled:opacity-60"
        :disabled="isSubmitting"
        type="submit"
      >
        {{ isSubmitting ? 'Criando...' : 'Criar conta' }}
      </button>
    </form>

    <p class="m-0 text-[13px] text-[#737373]">
      Ja tem conta?
      <RouterLink class="font-bold text-[#171717] no-underline hover:underline" to="/">
        Entrar
      </RouterLink>
    </p>
  </AuthLayout>
</template>

<script setup lang="ts">
import { Eye, EyeOff } from '@lucide/vue'
import { ref } from 'vue'
import { useRouter } from 'vue-router'

import AuthLayout from '@/layouts/AuthLayout.vue'
import { isApiError } from '@/shared/api/errors'
import { useAuthStore } from '@/stores/auth.store'

const name = ref('')
const username = ref('')
const password = ref('')
const showPassword = ref(false)
const isSubmitting = ref(false)
const formError = ref('')
const fieldErrors = ref<Record<string, string[]>>({})
const router = useRouter()
const auth = useAuthStore()

function fieldError(field: string): string {
  return fieldErrors.value[field]?.[0] ?? ''
}

async function submit() {
  isSubmitting.value = true
  formError.value = ''
  fieldErrors.value = {}

  try {
    await auth.register({
      name: name.value,
      username: username.value,
      password: password.value,
    })
    await router.push('/inbox')
  } catch (error) {
    if (isApiError(error)) {
      fieldErrors.value = error.fields ?? {}
      formError.value = error.message
    } else {
      formError.value = 'Não foi possível criar a conta agora.'
    }
  } finally {
    isSubmitting.value = false
  }
}
</script>
