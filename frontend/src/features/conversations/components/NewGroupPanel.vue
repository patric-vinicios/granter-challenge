<template>
  <form class="grid h-full grid-rows-[64px_auto_auto_minmax(0,1fr)_72px] bg-white" @submit.prevent>
    <header class="flex items-center gap-3 border-b border-[#e8e8e8] px-3">
      <button
        class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
        type="button"
        aria-label="Voltar"
        @click="$emit('close')"
      >
        <ArrowLeft :size="18" :stroke-width="2" aria-hidden="true" />
      </button>
      <div class="min-w-0">
        <strong class="block text-[18px] text-[#171717]">Novo grupo</strong>
        <span class="block text-[13px] text-[#a3a3a3]">{{ selectedContactIds.size }} de {{ contacts.length }} contatos selecionados</span>
      </div>
    </header>

    <section class="grid gap-2 px-3 py-5">
      <label class="text-[12px] font-bold text-[#737373]" for="group-name">Nome do grupo</label>
      <div class="grid grid-cols-[44px_minmax(0,1fr)] gap-3">
        <span
          class="grid h-11 w-11 place-items-center rounded-lg border border-[#e8e8e8] bg-[#fbfbfb] text-[#a3a3a3]"
          aria-hidden="true"
        >
          <UsersRound :size="18" :stroke-width="2" aria-hidden="true" />
        </span>
        <input
          id="group-name"
          :value="groupName"
          class="h-11 w-full rounded-lg border border-[#e8e8e8] bg-white px-4 text-[15px] font-bold text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          type="text"
          @input="$emit('update:groupName', ($event.target as HTMLInputElement).value)"
        />
      </div>
    </section>

    <div class="flex flex-wrap gap-2 border-b border-[#e8e8e8] px-3 pb-5">
      <button
        v-for="contact in selectedContacts"
        :key="contact.id"
        class="inline-flex h-8 items-center gap-2 rounded-full border border-[#e8e8e8] bg-[#fbfbfb] pl-1 pr-3 text-[13px] font-bold text-[#444444]"
        type="button"
        :aria-label="`Remover ${contact.user.name} da selecao`"
        @click="$emit('toggleContact', contact.user.id)"
      >
        <span class="grid h-6 w-6 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[10px]">
          {{ contactInitials(contact.user.name) }}
        </span>
        {{ contact.user.name }}
        <X :size="14" :stroke-width="2" class="text-[#a3a3a3]" aria-hidden="true" />
      </button>
    </div>

    <section class="min-h-0 overflow-hidden px-3 py-5">
      <div class="mb-3 text-[12px] font-bold uppercase text-[#a3a3a3]">Seus contatos</div>
      <label class="sr-only" for="contact-search">Buscar contato</label>
      <div class="relative mb-4">
        <Search
          class="absolute left-3 top-1/2 -translate-y-1/2 text-[#a3a3a3]"
          :size="16"
          :stroke-width="2"
          aria-hidden="true"
        />
        <input
          id="contact-search"
          v-model="contactSearchQuery"
          class="h-10 w-full rounded-lg border border-[#e8e8e8] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          placeholder="Buscar contato"
          type="text"
        />
      </div>

      <div class="max-h-full overflow-auto">
        <label
          v-for="contact in filteredContacts"
          :key="contact.id"
          class="grid min-h-[59px] grid-cols-[44px_minmax(0,1fr)_24px] items-center gap-3 text-[#171717]"
        >
          <span
            class="grid h-10 w-10 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[13px] font-bold text-[#444444]"
          >
            {{ contactInitials(contact.user.name) }}
          </span>
          <strong class="text-[15px]">{{ contact.user.name }}</strong>
          <input
            class="peer sr-only"
            type="checkbox"
            :checked="selectedContactIds.has(contact.user.id)"
            @change="$emit('toggleContact', contact.user.id)"
          />
          <span
            class="grid h-5 w-5 place-items-center rounded-md border border-[#d4d4d4] bg-white text-white peer-checked:border-black peer-checked:bg-black"
          >
            <Check :size="14" :stroke-width="3" aria-hidden="true" />
          </span>
        </label>
      </div>
    </section>

    <p
      v-if="error"
      class="mx-3 rounded-lg border border-[#fecaca] bg-[#fef2f2] p-3 text-[13px] text-[#dc2626]"
      role="alert"
    >
      {{ error }}
    </p>

    <footer class="grid grid-cols-2 gap-3 border-t border-[#e8e8e8] bg-white p-3">
      <button
        class="h-10 rounded-lg border border-[#e8e8e8] bg-white text-[14px] font-bold text-[#171717] hover:bg-[#f5f5f5]"
        type="button"
        @click="$emit('close')"
      >
        Cancelar
      </button>
      <button
        class="h-10 rounded-lg border border-black bg-black text-[14px] font-bold text-white hover:bg-[#222222]"
        :disabled="isSubmitting"
        type="button"
        @click="$emit('createGroup')"
      >
        {{ isSubmitting ? 'Criando...' : 'Criar grupo' }}
      </button>
    </footer>
  </form>
</template>

<script setup lang="ts">
import { ArrowLeft, Check, Search, UsersRound, X } from '@lucide/vue'
import { computed, ref } from 'vue'

import type { Contact } from '@/features/contacts/contacts.contracts'
import { contactInitials } from '@/features/contacts/contacts.store'

const props = defineProps<{
  contacts: Contact[]
  error: string | null
  isSubmitting: boolean
  selectedContactIds: Set<string>
  groupName: string
}>()

const contactSearchQuery = ref('')
const selectedContacts = computed(() => props.contacts.filter((contact) => props.selectedContactIds.has(contact.user.id)))
const filteredContacts = computed(() => {
  const query = contactSearchQuery.value.trim().toLocaleLowerCase()

  if (!query) {
    return props.contacts
  }

  return props.contacts.filter((contact) => {
    const searchable = `${contact.user.name} ${contact.user.username}`.toLocaleLowerCase()
    return searchable.includes(query)
  })
})

defineEmits<{
  close: []
  createGroup: []
  toggleContact: [userId: string]
  'update:groupName': [groupName: string]
}>()
</script>
