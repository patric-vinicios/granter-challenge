<template>
  <main class="h-full bg-[#f7f7f7]">
    <div
      class="grid h-full overflow-hidden bg-white min-[860px]:grid-cols-[418px_minmax(0,1fr)]"
    >
      <aside class="border-r border-[#e8e8e8] bg-white max-[859px]:hidden">
        <template v-if="sidebarMode === 'inbox'">
          <div class="grid grid-cols-[1fr_1fr_36px] gap-2 p-3">
            <button
              class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-[#e8e8e8] bg-white px-3 text-[13px] font-bold text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              @click="sidebarMode = 'new-group'"
            >
              <UserRoundPlus :size="16" :stroke-width="2" aria-hidden="true" />
              Novo grupo
            </button>
            <button
              class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-[#e8e8e8] bg-white px-3 text-[13px] font-bold text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              @click="sidebarMode = 'contacts'"
            >
              <UserRound :size="16" :stroke-width="2" aria-hidden="true" />
              Contatos
            </button>
            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Sair"
              title="Sair"
              @click="logout"
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
              @click="selectedConversationId = conversation.id"
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

        <section v-else-if="sidebarMode === 'contacts'" class="grid h-full grid-rows-[64px_auto_minmax(0,1fr)] bg-white">
          <header class="flex items-center gap-3 border-b border-[#e8e8e8] px-3">
            <strong class="min-w-0 flex-1 text-[18px] text-[#171717]">Contatos</strong>
            <button
              class="inline-flex h-9 items-center justify-center gap-2 rounded-lg border border-black bg-black px-3.5 text-[13px] font-bold text-white hover:bg-[#222222]"
              type="button"
              @click="openAddContact"
            >
              <Plus :size="16" :stroke-width="2" aria-hidden="true" />
              Adicionar
            </button>
            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Fechar contatos"
              @click="sidebarMode = 'inbox'"
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
                class="h-10 w-full rounded-lg border border-[#e8e8e8] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
                placeholder="Buscar contato"
                type="text"
              />
            </div>
          </div>

          <div class="min-h-0 overflow-auto px-3 py-4">
            <template v-for="group in contactGroups" :key="group.initial">
              <div class="mb-2 mt-1 text-[12px] font-bold uppercase text-[#a3a3a3]">
                {{ group.initial }}
              </div>
              <div
                v-for="contact in group.contacts"
                :key="contact.username"
                class="grid min-h-[72px] grid-cols-[44px_minmax(0,1fr)_34px] items-center gap-3"
              >
                <span
                  class="grid h-10 w-10 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[13px] font-bold text-[#444444]"
                >
                  {{ contact.initials }}
                </span>
                <span class="min-w-0">
                  <strong class="block truncate text-[15px] text-[#171717]">{{ contact.name }}</strong>
                  <span class="block truncate text-[13px] font-bold text-[#a3a3a3]">
                    @{{ contact.username }}
                  </span>
                </span>
                <button
                  class="grid h-8 w-8 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#737373] hover:bg-[#f5f5f5]"
                  type="button"
                  :aria-label="`Remover ${contact.name}`"
                >
                  <Trash2 :size="16" :stroke-width="2" aria-hidden="true" />
                </button>
              </div>
            </template>
          </div>
        </section>

        <form v-else class="grid h-full grid-rows-[64px_auto_auto_minmax(0,1fr)_72px] bg-white" @submit.prevent>
          <header class="flex items-center gap-3 border-b border-[#e8e8e8] px-3">
            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Voltar"
              @click="sidebarMode = 'inbox'"
            >
              <ArrowLeft :size="18" :stroke-width="2" aria-hidden="true" />
            </button>
            <div class="min-w-0">
              <strong class="block text-[18px] text-[#171717]">Novo grupo</strong>
              <span class="block text-[13px] text-[#a3a3a3]">3 de 8 contatos selecionados</span>
            </div>
          </header>

          <section class="grid gap-2 px-3 py-5">
            <label class="text-[12px] font-bold text-[#737373]" for="group-name">Nome do grupo</label>
            <div class="grid grid-cols-[44px_minmax(0,1fr)] gap-3">
              <button
                class="grid h-11 w-11 place-items-center rounded-lg border border-[#e8e8e8] bg-[#fbfbfb] text-[#a3a3a3]"
                type="button"
                aria-label="Imagem do grupo"
              >
                <UsersRound :size="18" :stroke-width="2" aria-hidden="true" />
              </button>
              <input
                id="group-name"
                v-model="groupName"
                class="h-11 w-full rounded-lg border border-[#e8e8e8] bg-white px-4 text-[15px] font-bold text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
                type="text"
              />
            </div>
          </section>

          <div class="flex flex-wrap gap-2 border-b border-[#e8e8e8] px-3 pb-5">
            <span
              v-for="contact in selectedGroupContacts"
              :key="contact.username"
              class="inline-flex h-8 items-center gap-2 rounded-full border border-[#e8e8e8] bg-[#fbfbfb] pl-1 pr-3 text-[13px] font-bold text-[#444444]"
            >
              <span class="grid h-6 w-6 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[10px]">
                {{ contact.initials }}
              </span>
              {{ contact.shortName }}
              <X :size="14" :stroke-width="2" class="text-[#a3a3a3]" aria-hidden="true" />
            </span>
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
                class="h-10 w-full rounded-lg border border-[#e8e8e8] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
                placeholder="Buscar contato"
                type="text"
              />
            </div>

            <div class="max-h-full overflow-auto">
              <label
                v-for="contact in groupContacts"
                :key="contact.username"
                class="grid min-h-[59px] grid-cols-[44px_minmax(0,1fr)_24px] items-center gap-3 text-[#171717]"
              >
                <span
                  class="grid h-10 w-10 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[13px] font-bold text-[#444444]"
                >
                  {{ contact.initials }}
                </span>
                <strong class="text-[15px]">{{ contact.name }}</strong>
                <input class="peer sr-only" type="checkbox" :checked="contact.selected" />
                <span
                  class="grid h-5 w-5 place-items-center rounded-md border border-[#d4d4d4] bg-white text-white peer-checked:border-black peer-checked:bg-black"
                >
                  <Check :size="14" :stroke-width="3" aria-hidden="true" />
                </span>
              </label>
            </div>
          </section>

          <footer class="grid grid-cols-2 gap-3 border-t border-[#e8e8e8] bg-white p-3">
            <button
              class="h-10 rounded-lg border border-[#e8e8e8] bg-white text-[14px] font-bold text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              @click="sidebarMode = 'inbox'"
            >
              Cancelar
            </button>
            <button
              class="h-10 rounded-lg border border-black bg-black text-[14px] font-bold text-white hover:bg-[#222222]"
              type="button"
              @click="sidebarMode = 'inbox'"
            >
              Criar grupo
            </button>
          </footer>
        </form>
      </aside>

      <section class="grid min-w-0 grid-rows-[64px_minmax(0,1fr)_72px] bg-[#fbfbfb]">
        <header class="border-b border-[#e8e8e8] bg-white px-5">
          <div
            v-if="isSearching"
            class="grid h-full grid-cols-[36px_minmax(0,1fr)_auto_36px_36px] items-center gap-2"
            @focusout="closeSearchOnFocusOut"
          >
            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Fechar busca"
              @click="isSearching = false"
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
                v-model="searchTerm"
                class="h-10 w-full rounded-lg border border-[#171717] bg-white pl-9 pr-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
                autofocus
                type="text"
              />
            </div>

            <span class="px-1 text-[13px] text-[#a3a3a3]">1 / 1</span>

            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Resultado anterior"
            >
              <ChevronUp :size="17" :stroke-width="2" aria-hidden="true" />
            </button>

            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Proximo resultado"
            >
              <ChevronDown :size="17" :stroke-width="2" aria-hidden="true" />
            </button>
          </div>

          <div v-else class="flex h-full items-center gap-3">
            <span
              class="grid h-[40px] w-[40px] place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[13px] font-bold text-[#444444]"
            >
              {{ selectedConversation.initials }}
            </span>
            <div class="min-w-0 flex-1">
              <strong class="block truncate text-[15px] text-[#171717]">
                {{ selectedConversation.name }}
              </strong>
              <span class="block truncate text-[13px] text-[#737373]">
                {{ selectedConversation.subtitle }}
              </span>
            </div>
            <button
              class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
              type="button"
              aria-label="Buscar na conversa"
              @click="openSearch"
            >
              <Search :size="18" :stroke-width="2" aria-hidden="true" />
            </button>
          </div>
        </header>

        <div class="overflow-auto px-6 py-7 min-[860px]:px-[150px]">
          <div
            class="mx-auto mb-7 w-max rounded-full border border-[#e8e8e8] bg-white px-3 py-1 text-[12px] text-[#a3a3a3]"
          >
            Hoje
          </div>

          <div class="grid gap-2">
            <MessageBubble
              v-for="message in selectedConversation.messages"
              :key="`${message.time}-${message.text}`"
              :side="message.side"
              :text="message.text"
              :time="message.time"
              :wide="message.wide"
              :author="selectedConversation.type === 'group' ? message.author : undefined"
            />
          </div>
        </div>

        <form
          class="grid grid-cols-[minmax(0,1fr)_44px] gap-3 border-t border-[#e8e8e8] bg-white px-5 py-4"
          @submit.prevent
        >
          <label class="sr-only" for="message">Mensagem</label>
          <textarea
            id="message"
            v-model="messageDraft"
            class="min-h-12 resize-none rounded-lg border border-[#e8e8e8] bg-white px-4 py-3 text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
            placeholder="Escreva uma mensagem..."
            rows="1"
            @keydown.ctrl.enter.prevent="sendMessage"
          />
          <button
            class="grid h-12 w-11 place-items-center rounded-lg border border-black bg-black text-white hover:bg-[#222222]"
            type="button"
            aria-label="Enviar mensagem"
            @click="sendMessage"
          >
            <Navigation fill="currentColor" :size="18" :stroke-width="2" aria-hidden="true" />
          </button>
        </form>
      </section>
    </div>

    <div
      v-if="isAddContactOpen"
      class="fixed inset-0 grid place-items-center bg-black/30 p-6"
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-contact-title"
    >
      <form
        class="w-full max-w-[430px] overflow-hidden rounded-[10px] border border-[#e8e8e8] bg-white shadow-[0_24px_72px_rgba(0,0,0,0.24)]"
        @submit.prevent="addContact"
      >
        <header class="flex items-center gap-3 border-b border-[#e8e8e8] p-5">
          <button
            class="grid h-9 w-9 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#171717] hover:bg-[#f5f5f5]"
            type="button"
            aria-label="Voltar"
            @click="closeAddContact"
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
                v-model.trim="contactUsername"
                class="h-11 min-w-0 flex-1 rounded-lg border bg-white px-4 text-[15px] text-[#171717] placeholder:text-[#a3a3a3] focus:outline-2 focus:outline-offset-1 focus:outline-black"
                :class="contactFeedback === 'error' ? 'border-[#ef4444]' : 'border-[#e8e8e8]'"
                placeholder="@anabeatriz"
                type="text"
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
              v-if="contactFeedback === 'success'"
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
              v-else-if="contactFeedback === 'error'"
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
  </main>
</template>

<script setup lang="ts">
import {
  ArrowLeft,
  Check,
  ChevronDown,
  ChevronUp,
  LogOut,
  Navigation,
  Plus,
  Search,
  Trash2,
  UserRound,
  UserRoundPlus,
  UsersRound,
  X,
} from '@lucide/vue'
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'

import MessageBubble from '@/components/MessageBubble.vue'

type Message = {
  side: 'in' | 'out'
  text: string
  time: string
  wide?: boolean
  author?: string
}

type Conversation = {
  id: string
  type: 'private' | 'group'
  initials: string
  name: string
  subtitle: string
  preview: string
  time: string
  messages: Message[]
}

const selectedConversationId = ref('ana')
const router = useRouter()
const sidebarMode = ref<'inbox' | 'new-group' | 'contacts'>('inbox')
const isSearching = ref(false)
const isAddContactOpen = ref(false)
const searchTerm = ref('')
const messageDraft = ref('')
const groupName = ref('Squad Lancamento')
const contactUsername = ref('')
const contactFeedback = ref<'idle' | 'success' | 'error'>('idle')

const groupContacts = [
  { initials: 'AB', name: 'Ana Beatriz', shortName: 'Ana', username: 'anabeatriz', selected: true },
  { initials: 'CE', name: 'Carlos Eduardo', shortName: 'Carlos', username: 'carloseduardo', selected: true },
  { initials: 'MS', name: 'Mariana Silva', shortName: 'Mariana', username: 'marianasilva', selected: true },
  { initials: 'JP', name: 'Joao Pedro', shortName: 'Joao', username: 'joaopedro', selected: false },
  { initials: 'LM', name: 'Leticia Moraes', shortName: 'Leticia', username: 'leticiamoraes', selected: false },
]

const contactGroups = [
  {
    initial: 'A',
    contacts: [{ initials: 'AB', name: 'Ana Beatriz', username: 'anabeatriz' }],
  },
  {
    initial: 'C',
    contacts: [{ initials: 'CE', name: 'Carlos Eduardo', username: 'carlosedu' }],
  },
  {
    initial: 'J',
    contacts: [{ initials: 'JP', name: 'Joao Pedro', username: 'joaopedro' }],
  },
  {
    initial: 'L',
    contacts: [{ initials: 'LM', name: 'Leticia Moraes', username: 'leticiam' }],
  },
  {
    initial: 'M',
    contacts: [
      { initials: 'MS', name: 'Mariana Silva', username: 'marianas' },
      { initials: 'RA', name: 'Rafael Alves', username: 'rafaelalves' },
    ],
  },
]

const conversations: Conversation[] = [
  {
    id: 'ana',
    type: 'private',
    initials: 'AB',
    name: 'Ana Beatriz',
    subtitle: 'visto por ultimo ha 5 min',
    preview: 'Voce: Perfeito, fico no aguardo entao',
    time: '14:33',
    messages: [
      { side: 'in', text: 'Oi! Conseguiu ver a proposta que te enviei?', time: '14:20' },
      { side: 'out', text: 'Vi sim, ficou otima', time: '14:24' },
      {
        side: 'out',
        text: 'So queria ajustar a parte de cronograma antes de fechar',
        time: '14:24',
        wide: true,
      },
      {
        side: 'in',
        text: 'Boa, faz sentido. Consigo mexer nisso hoje a tarde',
        time: '14:29',
        wide: true,
      },
      { side: 'in', text: 'Te mando a versao revisada ainda hoje', time: '14:32' },
      { side: 'out', text: 'Perfeito, fico no aguardo entao', time: '14:33' },
    ],
  },
  {
    id: 'produto',
    type: 'group',
    initials: 'TP',
    name: 'Time de Produto',
    subtitle: '5 membros · Voce, Rafael, Ana, +2',
    preview: 'Voce: Combinado, obrigado pessoal',
    time: '10:03',
    messages: [
      {
        side: 'in',
        author: 'Rafael Alves',
        text: 'Bom dia pessoal! Subi a build de staging pra validacao',
        time: '09:12',
        wide: true,
      },
      { side: 'in', author: 'Ana Beatriz', text: 'Testando agora, ja te falo', time: '09:20' },
      {
        side: 'out',
        text: 'Aqui rodou tudo certo, so o login que ta lento',
        time: '09:34',
        wide: true,
      },
      { side: 'in', author: 'Leticia Moraes', text: 'E o cache, ja to resolvendo', time: '09:41' },
      {
        side: 'in',
        author: 'Rafael Alves',
        text: 'Show. Assim que subir o fix eu aviso aqui',
        time: '09:57',
        wide: true,
      },
      { side: 'out', text: 'Combinado, obrigado pessoal', time: '10:03' },
    ],
  },
  {
    id: 'carlos',
    type: 'private',
    initials: 'CE',
    name: 'Carlos Eduardo',
    subtitle: 'visto por ultimo ha 18 min',
    preview: 'Bora marcar aquele cafe',
    time: '12:10',
    messages: [{ side: 'in', text: 'Bora marcar aquele cafe', time: '12:10' }],
  },
  {
    id: 'familia',
    type: 'group',
    initials: 'FM',
    name: 'Familia',
    subtitle: '4 membros · Voce, Mae, Joao, +1',
    preview: 'Mae: nao esquecam do almoco',
    time: 'Ontem',
    messages: [{ side: 'in', author: 'Mae', text: 'Nao esquecam do almoco', time: 'Ontem' }],
  },
  {
    id: 'mariana',
    type: 'private',
    initials: 'MS',
    name: 'Mariana Silva',
    subtitle: 'offline',
    preview: 'valeu pela ajuda de ontem',
    time: 'Ontem',
    messages: [{ side: 'in', text: 'valeu pela ajuda de ontem', time: 'Ontem' }],
  },
  {
    id: 'joao',
    type: 'private',
    initials: 'JP',
    name: 'Joao Pedro',
    subtitle: 'visto por ultimo ontem',
    preview: 'Combinado entao, te encontro amanha as...',
    time: 'Seg',
    messages: [{ side: 'in', text: 'Combinado entao, te encontro amanha as 9', time: 'Seg' }],
  },
]

const selectedConversation = computed(
  () => conversations.find((conversation) => conversation.id === selectedConversationId.value) ?? conversations[0],
)

const selectedGroupContacts = computed(() => groupContacts.filter((contact) => contact.selected))

function openSearch() {
  searchTerm.value = ''
  isSearching.value = true
}

function closeSearchOnFocusOut(event: FocusEvent) {
  const nextTarget = event.relatedTarget

  if (nextTarget instanceof Node && event.currentTarget instanceof Node) {
    if (event.currentTarget.contains(nextTarget)) {
      return
    }
  }

  isSearching.value = false
}

function sendMessage() {
  messageDraft.value = ''
}

function logout() {
  router.push('/')
}

function openAddContact() {
  contactUsername.value = ''
  contactFeedback.value = 'idle'
  isAddContactOpen.value = true
}

function closeAddContact() {
  isAddContactOpen.value = false
}

function addContact() {
  contactFeedback.value = contactUsername.value.replace('@', '') === 'fulano123' ? 'error' : 'success'
}
</script>
