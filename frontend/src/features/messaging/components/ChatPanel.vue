<template>
  <section class="grid h-full min-h-0 min-w-0 grid-rows-[64px_minmax(0,1fr)_72px] bg-[#fbfbfb]">
    <header class="border-b border-[#e8e8e8] bg-white px-5">
      <div
        v-if="isSearching"
        class="grid h-full grid-cols-[36px_minmax(0,1fr)_auto_36px_36px] items-center gap-2"
        @focusout="$emit('searchFocusout', $event)"
      >
        <button
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
          type="button"
          aria-label="Fechar busca"
          @click="$emit('closeSearch')"
        >
          <X :size="17" :stroke-width="2" aria-hidden="true" />
        </button>

        <label class="sr-only" for="message-search">Buscar na conversa</label>
        <div class="relative">
          <Search
            class="absolute left-3 top-1/2 -translate-y-1/2 text-[#737373]"
            :size="16"
            :stroke-width="2"
            aria-hidden="true"
          />
          <input
            id="message-search"
            :value="searchTerm"
            class="h-10 w-full rounded-lg border border-[#171717] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
            autofocus
            type="text"
            @input="$emit('update:searchTerm', ($event.target as HTMLInputElement).value)"
          />
        </div>

        <span
          class="min-w-14 px-1 text-center text-[13px]"
          :class="searchStatus === 'error' || searchStatus === 'validation' ? 'text-[#991b1b]' : 'text-[#737373]'"
          role="status"
        >
          {{ searchStatusLabel }}
        </span>

        <button
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
          type="button"
          aria-label="Resultado anterior"
          :disabled="!canNavigateSearch"
          @click="$emit('previousSearchResult')"
        >
          <ChevronUp :size="17" :stroke-width="2" aria-hidden="true" />
        </button>

        <button
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
          type="button"
          aria-label="Proximo resultado"
          :disabled="!canNavigateSearch"
          @click="$emit('nextSearchResult')"
        >
          <ChevronDown :size="17" :stroke-width="2" aria-hidden="true" />
        </button>
      </div>

      <div v-else class="flex h-full items-center gap-3">
        <button
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5] min-[860px]:hidden"
          type="button"
          aria-label="Voltar para conversas"
          @click="$emit('closeConversation')"
        >
          <ArrowLeft :size="18" :stroke-width="2" aria-hidden="true" />
        </button>
        <span
          class="grid h-[40px] w-[40px] place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[13px] font-bold text-[#444444]"
        >
          {{ conversation.initials }}
        </span>
        <div class="min-w-0 flex-1">
          <strong class="block truncate text-[15px] text-[#171717]">
            {{ conversation.name }}
          </strong>
          <span class="block truncate text-[13px] text-[#737373]">
            {{ realtimeError ?? conversation.subtitle }}
          </span>
        </div>
        <button
          v-if="conversation.type === 'group'"
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
          type="button"
          aria-label="Gerenciar grupo"
          @click="$emit('openGroupDetails')"
        >
          <UsersRound :size="18" :stroke-width="2" aria-hidden="true" />
        </button>
        <button
          class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
          type="button"
          aria-label="Buscar na conversa"
          @click="$emit('openSearch')"
        >
          <Search :size="18" :stroke-width="2" aria-hidden="true" />
        </button>
      </div>
    </header>

    <div
      ref="messageScroller"
      aria-label="Mensagens da conversa"
      role="log"
      class="min-h-0 overflow-y-auto overflow-x-hidden px-6 py-7 min-[860px]:px-[150px]"
    >
      <div
        class="mx-auto mb-7 w-max rounded-full border border-[#e8e8e8] bg-white px-3 py-1 text-[12px] text-[#a3a3a3]"
      >
        Hoje
      </div>

      <div class="grid gap-2">
        <button
          v-if="canLoadOlder"
          class="mx-auto mb-5 rounded-lg border border-[#e8e8e8] bg-white px-4 py-2 text-[13px] font-medium text-[#171717] hover:bg-[#f5f5f5] disabled:cursor-not-allowed disabled:text-[#a3a3a3]"
          type="button"
          :disabled="isLoadingOlder"
          @click="$emit('loadOlderMessages')"
        >
          {{ isLoadingOlder ? 'Carregando...' : 'Carregar mensagens anteriores' }}
        </button>

        <p v-if="isLoadingHistory" class="py-10 text-center text-[14px] text-[#737373]">
          Carregando historico...
        </p>
        <p v-else-if="historyError" class="py-10 text-center text-[14px] text-[#737373]">
          {{ historyError }}
        </p>
        <p v-else-if="conversation.messages.length === 0" class="py-10 text-center text-[14px] text-[#737373]">
          Nenhuma mensagem nesta conversa.
        </p>
        <template v-else>
          <MessageBubble
            v-for="(message, index) in conversation.messages"
            :key="messageKey(message, index)"
            :side="message.side"
            :text="message.text"
            :time="message.time"
            :wide="message.wide"
            :author="conversation.type === 'group' ? message.author : undefined"
            :is-highlighted="message.id === searchActiveMessageId"
            :highlight-ranges="message.id === searchActiveMessageId ? searchActiveMatchOffsets : []"
          />
        </template>
      </div>
    </div>

    <form
      class="grid grid-cols-[minmax(0,1fr)_44px] gap-3 border-t border-[#e8e8e8] bg-white px-5 py-4"
      @submit.prevent="$emit('sendMessage')"
    >
      <label class="sr-only" for="message">Mensagem</label>
      <textarea
        id="message"
        :value="messageDraft"
        class="min-h-12 resize-none rounded-lg border border-[#e8e8e8] bg-white px-4 py-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
        placeholder="Escreva uma mensagem..."
        rows="1"
        @input="$emit('update:messageDraft', ($event.target as HTMLTextAreaElement).value)"
        @keydown.ctrl.enter.prevent="$emit('sendMessage')"
      />
      <button
        class="grid h-12 w-11 place-items-center rounded-lg border border-black bg-black text-white hover:bg-[#222222]"
        :class="{ 'opacity-50': !canSendMessage }"
        type="submit"
        aria-label="Enviar mensagem"
        :disabled="!canSendMessage"
      >
        <Navigation fill="currentColor" :size="18" :stroke-width="2" aria-hidden="true" />
      </button>
    </form>
  </section>
</template>

<script setup lang="ts">
import { ArrowLeft, ChevronDown, ChevronUp, Navigation, Search, UsersRound, X } from '@lucide/vue'
import { computed, nextTick, useTemplateRef, watch } from 'vue'

import MessageBubble from '@/components/MessageBubble.vue'
import type { ChatConversation } from '@/types/chat'
import type { ConversationSearchStatus, SearchMatchOffset } from '@/types/search'

const props = defineProps<{
  conversation: ChatConversation
  canSendMessage: boolean
  isSearching: boolean
  isLoadingHistory: boolean
  isLoadingOlder: boolean
  canLoadOlder: boolean
  historyError: string | null
  searchTerm: string
  messageDraft: string
  realtimeError: string | null
  searchStatus: ConversationSearchStatus
  searchError: string | null
  searchActivePosition: number | null
  searchTotalMatches: number
  searchTruncated: boolean
  searchActiveMessageId: string | null
  searchActiveMatchOffsets: SearchMatchOffset[]
}>()

const messageScroller = useTemplateRef<HTMLElement>('messageScroller')
let previousScrollHeight = 0

watch(
  () => ({
    conversationId: props.conversation.id,
    messageIds: props.conversation.messages.map(messageIdentity),
    isLoadingHistory: props.isLoadingHistory,
  }),
  (current, previous) => {
    const shouldPreservePosition =
      previous?.conversationId === current.conversationId &&
      messagesWerePrepended(previous.messageIds, current.messageIds)
    const previousScrollTop = messageScroller.value?.scrollTop ?? 0

    void nextTick(() => {
      const scroller = messageScroller.value

      if (!scroller) {
        return
      }

      if (shouldPreservePosition) {
        scroller.scrollTop = previousScrollTop + Math.max(0, scroller.scrollHeight - previousScrollHeight)
      } else {
        scroller.scrollTop = scroller.scrollHeight
      }

      previousScrollHeight = scroller.scrollHeight
    })
  },
  { flush: 'post', immediate: true },
)

defineEmits<{
  closeSearch: []
  closeConversation: []
  openGroupDetails: []
  openSearch: []
  loadOlderMessages: []
  nextSearchResult: []
  previousSearchResult: []
  searchFocusout: [event: FocusEvent]
  sendMessage: []
  'update:searchTerm': [searchTerm: string]
  'update:messageDraft': [messageDraft: string]
}>()

const canNavigateSearch = computed(() => props.searchTotalMatches > 1 && props.searchStatus === 'success')

const searchStatusLabel = computed(() => {
  if (props.searchStatus === 'loading') {
    return 'Buscando...'
  }

  if (props.searchStatus === 'validation' || props.searchStatus === 'error') {
    return props.searchError ?? 'Falha'
  }

  if (props.searchStatus === 'success') {
    if (props.searchTotalMatches === 0) {
      return '0 / 0'
    }

    const total = props.searchTruncated ? `${props.searchTotalMatches}+` : String(props.searchTotalMatches)

    return `${props.searchActivePosition ?? 1} / ${total}`
  }

  return '0 / 0'
})

function messageIdentity(message: ChatConversation['messages'][number]): string {
  return message.id ?? message.clientRef ?? `${message.side}:${message.time}:${message.author ?? ''}:${message.text}`
}

function messageKey(message: ChatConversation['messages'][number], index: number): string {
  return message.id ?? message.clientRef ?? `${messageIdentity(message)}:${index}`
}

function messagesWerePrepended(previousIds: string[], currentIds: string[]): boolean {
  const addedCount = currentIds.length - previousIds.length

  if (addedCount <= 0) {
    return false
  }

  return previousIds.every((id, index) => currentIds[addedCount + index] === id)
}
</script>
