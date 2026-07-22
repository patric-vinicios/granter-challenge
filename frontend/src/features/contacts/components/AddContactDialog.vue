<template>
  <div
    class="fixed inset-0 grid place-items-center bg-black/30 p-6"
    role="dialog"
    aria-modal="true"
    aria-labelledby="add-contact-title"
  >
    <form
      class="w-full max-w-[430px] overflow-hidden rounded-[10px] border border-[#e8e8e8] bg-white shadow-[0_24px_72px_rgba(0,0,0,0.24)]"
      @submit.prevent="$emit('addContact')"
    >
      <header class="flex items-center gap-3 border-b border-[#e8e8e8] p-5">
        <button
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
          type="button"
          aria-label="Voltar"
          @click="$emit('close')"
        >
          <ArrowLeft :size="18" :stroke-width="2" aria-hidden="true" />
        </button>
        <div class="min-w-0">
          <strong id="add-contact-title" class="block text-[18px] text-[#171717]">
            Adicionar contato
          </strong>
          <span class="block text-[13px] text-[#a3a3a3]">
            Informe o @usuario que deseja adicionar
          </span>
        </div>
      </header>

      <section class="grid gap-4 p-5">
        <div class="grid gap-2">
          <label class="text-[12px] font-bold text-[#737373]" for="add-contact-username">
            Usuario
          </label>
          <div class="flex items-start gap-2">
            <input
              id="add-contact-username"
              :value="username"
              class="h-11 min-w-0 flex-1 rounded-lg border bg-white px-4 text-[15px] text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
              :class="feedback === 'error' ? 'border-[#ef4444]' : 'border-[#e8e8e8]'"
              placeholder="@anabeatriz"
              type="text"
              @input="$emit('update:username', ($event.target as HTMLInputElement).value.trim())"
            />
            <button
              class="h-11 w-[100px] shrink-0 rounded-lg border border-black bg-black px-3 text-[14px] font-bold text-white hover:bg-[#222222]"
              type="submit"
            >
              Adicionar
            </button>
          </div>
        </div>

        <div class="min-h-[64px]">
          <div
            v-if="feedback === 'success'"
            class="grid grid-cols-[28px_minmax(0,1fr)] gap-3 rounded-lg border border-[#bbf7d0] bg-[#ecfdf3] p-3 text-[#15803d]"
          >
            <span class="grid h-6 w-6 place-items-center rounded-full bg-[#16a34a] text-white">
              <Check :size="15" :stroke-width="3" aria-hidden="true" />
            </span>
            <span class="min-w-0 text-[13px]">
              <strong class="block text-[14px]">Contato adicionado</strong>
              Ana Beatriz (@anabeatriz) entrou na sua lista.
            </span>
          </div>

          <div
            v-else-if="feedback === 'error'"
            class="grid grid-cols-[28px_minmax(0,1fr)] gap-3 rounded-lg border border-[#fecaca] bg-[#fef2f2] p-3 text-[#dc2626]"
          >
            <span class="grid h-6 w-6 place-items-center rounded-full bg-[#ef4444] text-white">
              <X :size="15" :stroke-width="3" aria-hidden="true" />
            </span>
            <span class="min-w-0 text-[13px]">
              <strong class="block text-[14px]">Usuario nao encontrado</strong>
              Nenhum usuario com @fulano123 existe no sistema.
            </span>
          </div>
        </div>
      </section>
    </form>
  </div>
</template>

<script setup lang="ts">
import { ArrowLeft, Check, X } from '@lucide/vue'

defineProps<{
  username: string
  feedback: 'idle' | 'success' | 'error'
}>()

defineEmits<{
  'update:username': [username: string]
  addContact: []
  close: []
}>()
</script>
