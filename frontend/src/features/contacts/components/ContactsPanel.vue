<template>
  <section class="grid h-full grid-rows-[64px_auto_minmax(0,1fr)] bg-white">
    <header class="flex items-center gap-3 border-b border-[#e8e8e8] px-3">
      <strong class="min-w-0 flex-1 text-[18px] text-[#171717]">Contatos</strong>
      <button
        class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-black bg-black px-3.5 text-[13px] font-bold text-white hover:bg-[#222222]"
        type="button"
        @click="$emit('addContact')"
      >
        <Plus :size="16" :stroke-width="2" aria-hidden="true" />
        Adicionar
      </button>
      <button
        class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
        type="button"
        aria-label="Fechar contatos"
        @click="$emit('close')"
      >
        <X :size="17" :stroke-width="2" aria-hidden="true" />
      </button>
    </header>

    <div class="border-b border-[#e8e8e8] px-3 py-4">
      <label class="sr-only" for="contacts-search">Buscar contato</label>
      <div class="relative">
        <Search
          class="absolute left-3 top-1/2 -translate-y-1/2 text-[#a3a3a3]"
          :size="16"
          :stroke-width="2"
          aria-hidden="true"
        />
        <input
          id="contacts-search"
          v-model="searchQuery"
          class="h-10 w-full rounded-lg border border-[#e8e8e8] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          placeholder="Buscar contato"
          type="text"
        />
      </div>
    </div>

    <div class="min-h-0 overflow-auto px-3 py-4">
      <div v-if="isLoading" class="py-10 text-center text-[14px] text-[#737373]" role="status">
        Carregando contatos...
      </div>

      <div v-else-if="error" class="rounded-lg border border-[#fecaca] bg-[#fef2f2] p-3 text-[13px] text-[#dc2626]" role="alert">
        {{ error }}
      </div>

      <div v-else-if="isEmpty" class="py-10 text-center text-[14px] text-[#737373]">
        Nenhum contato adicionado.
      </div>

      <p v-else-if="filteredContactGroups.length === 0" class="py-10 text-center text-[14px] text-[#737373]">
        Nenhum contato encontrado.
      </p>

      <template v-else v-for="group in filteredContactGroups" :key="group.initial">
        <div class="mb-2 mt-1 text-[12px] font-bold uppercase text-[#a3a3a3]">
          {{ group.initial }}
        </div>
        <div
          v-for="contact in group.contacts"
          :key="contact.id"
          class="grid min-h-[72px] grid-cols-[44px_minmax(0,1fr)_34px_34px] items-center gap-3"
        >
          <span
            class="grid h-10 w-10 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[13px] font-bold text-[#444444]"
          >
            {{ userInitials(contact.user.name) }}
          </span>
          <span class="min-w-0">
            <strong class="block truncate text-[15px] text-[#171717]">{{ contact.user.name }}</strong>
            <span class="block truncate text-[13px] font-bold text-[#a3a3a3]">
              @{{ contact.user.username }}
            </span>
          </span>
          <button
            class="grid h-8 w-8 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#737373] hover:bg-[#f5f5f5]"
            type="button"
            :aria-label="`Abrir conversa com ${contact.user.name}`"
            :disabled="pendingConversationUserIds.has(contact.user.id)"
            @click="$emit('openConversation', contact.user.id)"
          >
            <MessageCircle :size="16" :stroke-width="2" aria-hidden="true" />
          </button>
          <button
            class="grid h-8 w-8 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#737373] hover:bg-[#f5f5f5]"
            type="button"
            :aria-label="`Remover ${contact.user.name}`"
            :disabled="pendingRemovalIds.has(contact.id)"
            @click="$emit('removeContact', contact.id)"
          >
            <Trash2 :size="16" :stroke-width="2" aria-hidden="true" />
          </button>
        </div>
      </template>
    </div>
  </section>
</template>

<script setup lang="ts">
import { MessageCircle, Plus, Search, Trash2, X } from '@lucide/vue'
import { computed, ref } from 'vue'

import { useDebouncedValue } from '@/shared/reactivity/useDebouncedValue'
import { matchesUserQuery } from '@/shared/user/matchesUserQuery'
import { userInitials } from '@/shared/user/userInitials'

import type { ContactGroup } from '../contacts.contracts'

const props = defineProps<{
  contactGroups: ContactGroup[]
  error: string | null
  isEmpty: boolean
  isLoading: boolean
  pendingConversationUserIds: Set<string>
  pendingRemovalIds: Set<string>
}>()

const searchQuery = ref('')
const debouncedSearchQuery = useDebouncedValue(searchQuery, {
  delayMs: 800,
  immediateWhen: (value) => value.trim() === '',
})
const filteredContactGroups = computed(() => {
  const query = debouncedSearchQuery.value

  if (!query.trim()) {
    return props.contactGroups
  }

  return props.contactGroups
    .map((group) => ({
      ...group,
      contacts: group.contacts.filter((contact) =>
        matchesUserQuery(contact.user, query),
      ),
    }))
    .filter((group) => group.contacts.length > 0)
})

defineEmits<{
  addContact: []
  close: []
  openConversation: [userId: string]
  removeContact: [contactId: string]
}>()
</script>
