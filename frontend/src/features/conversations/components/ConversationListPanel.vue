<template>
  <div class="grid grid-cols-[1fr_1fr_36px] gap-2 p-3">
      <button
        class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-[#e8e8e8] bg-white px-3 text-[13px] font-bold text-[#171717] hover:bg-[#f5f5f5]"
        type="button"
        @click="$emit('createGroup')"
      >
        <UserRoundPlus :size="16" :stroke-width="2" aria-hidden="true" />
        Novo grupo
      </button>
      <button
        class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-[#e8e8e8] bg-white px-3 text-[13px] font-bold text-[#171717] hover:bg-[#f5f5f5]"
        type="button"
        @click="$emit('openContacts')"
      >
        <UserRound :size="16" :stroke-width="2" aria-hidden="true" />
        Contatos
      </button>
      <button
        class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
        type="button"
        aria-label="Sair"
        title="Sair"
        @click="$emit('logout')"
      >
        <LogOut :size="17" :stroke-width="2" aria-hidden="true" />
      </button>
  </div>

  <div class="px-3 pb-3">
      <label class="sr-only" for="conversation-search">Buscar</label>
      <div class="relative">
        <Search
          class="absolute left-3 top-1/2 -translate-y-1/2 text-[#a3a3a3]"
          :size="16"
          :stroke-width="2"
          aria-hidden="true"
        />
        <input
          id="conversation-search"
          class="h-9 w-full rounded-lg border border-[#e8e8e8] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
          placeholder="Buscar"
          type="text"
        />
      </div>
  </div>

  <nav class="grid gap-1 px-2">
      <button
        v-for="conversation in conversations"
        :key="conversation.id"
        class="grid min-h-[65px] grid-cols-[46px_minmax(0,1fr)_auto] items-center gap-3 rounded-lg px-3 text-left hover:bg-[#f5f5f5]"
        :class="{ 'bg-[#f0f0f0]': conversation.id === selectedConversationId }"
        type="button"
        @click="$emit('selectConversation', conversation.id)"
      >
        <span
          class="grid h-[46px] w-[46px] place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[14px] font-bold text-[#444444]"
        >
          {{ conversation.initials }}
        </span>
        <span class="min-w-0">
          <strong class="block truncate text-[15px] text-[#171717]">
            {{ conversation.name }}
          </strong>
          <span class="block truncate text-[14px] text-[#737373]">
            {{ conversation.preview }}
          </span>
        </span>
        <span class="text-[12px] text-[#a3a3a3]">{{ conversation.time }}</span>
      </button>
  </nav>
</template>

<script setup lang="ts">
import { LogOut, Search, UserRound, UserRoundPlus } from '@lucide/vue'

import type { Conversation } from '../conversations.mock'

defineProps<{
  conversations: Conversation[]
  selectedConversationId: string
}>()

defineEmits<{
  createGroup: []
  openContacts: []
  logout: []
  selectConversation: [conversationId: string]
}>()
</script>
