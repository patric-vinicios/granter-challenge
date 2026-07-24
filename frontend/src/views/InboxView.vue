<template>
  <main class="h-full min-h-0 overflow-hidden bg-[#f7f7f7]">
    <div
      class="grid h-full min-h-0 overflow-hidden bg-white min-[860px]:grid-cols-[418px_minmax(0,1fr)]"
    >
      <aside
        class="min-h-0 border-r border-[#e8e8e8] bg-white"
        :class="isMobileListVisible ? 'max-[859px]:grid' : 'max-[859px]:hidden'"
      >
        <ConversationListPanel
          v-if="sidebarMode === 'inbox'"
          v-model:search-query="inboxSearchQuery"
          :conversations="conversationItems"
          :error="inboxLoadError"
          :is-empty="isInboxEmpty"
          :is-loading="isInboxLoading"
          :selected-conversation-id="selectedConversation?.id ?? ''"
          @create-group="sidebarMode = 'new-group'"
          @open-contacts="sidebarMode = 'contacts'"
          @logout="logout"
          @select-conversation="selectConversation"
        />

        <ContactsPanel
          v-else-if="sidebarMode === 'contacts'"
          :contact-groups="contactGroups"
          :error="loadError"
          :is-empty="isEmpty"
          :is-loading="isLoading"
          :pending-conversation-user-ids="pendingPrivateUserIds"
          :pending-removal-ids="pendingRemovalIds"
          @add-contact="openAddContact"
          @close="sidebarMode = 'inbox'"
          @open-conversation="openPrivateConversation"
          @remove-contact="removeContact"
        />

        <NewGroupPanel
          v-else-if="sidebarMode === 'new-group'"
          v-model:group-name="groupName"
          :contacts="contacts"
          :error="groupError"
          :is-submitting="isSavingGroup"
          :selected-contact-ids="selectedGroupContactIds"
          @close="sidebarMode = 'inbox'"
          @create-group="createGroup"
          @toggle-contact="toggleGroupContact"
        />

        <GroupDetailsPanel
          v-else-if="selectedGroupConversation && currentUserId"
          :contacts="contacts"
          :current-user-id="currentUserId"
          :error="groupError"
          :group="selectedGroupConversation"
          :pending-user-ids="pendingMemberUserIds"
          @add-member="addGroupMember"
          @close="sidebarMode = 'inbox'"
          @leave-group="leaveSelectedGroup"
          @remove-member="removeGroupMember"
        />
      </aside>

      <ChatPanel
        v-model:message-draft="messageDraft"
        v-model:search-term="searchTerm"
        :can-send-message="canSendMessage"
        :can-load-older="selectedHistoryState.hasMore"
        :conversation="selectedConversation"
        :history-error="selectedHistoryState.error"
        :is-searching="isSearching"
        :realtime-error="realtimeError"
        :is-loading-history="selectedHistoryState.isLoadingInitial"
        :is-loading-older="selectedHistoryState.isLoadingOlder"
        :search-active-match-offsets="searchActiveMatchOffsets"
        :search-active-message-id="searchActiveMessageId"
        :search-active-position="searchActivePosition"
        :search-error="conversationSearchError"
        :search-status="conversationSearchStatus"
        :search-total-matches="searchTotalMatches"
        :search-truncated="searchTruncated"
        @close-search="closeSearch"
        @close-conversation="showMobileConversationList"
        @load-older-messages="loadOlderMessages"
        @next-search-result="selectNextSearchResult"
        @open-group-details="openGroupDetails"
        @open-search="openSearch"
        @previous-search-result="selectPreviousSearchResult"
        @search-focusout="closeSearchOnFocusOut"
        @send-message="sendMessage"
        :class="{ 'max-[859px]:hidden': isMobileListVisible }"
      />
    </div>

    <AddContactDialog
      v-if="isAddContactOpen"
      v-model:username="contactUsername"
      :feedback="contactFeedback"
      :is-submitting="isAddingContact"
      @add-contact="addContact"
      @close="closeAddContact"
    />
  </main>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'

import AddContactDialog from '@/features/contacts/components/AddContactDialog.vue'
import ContactsPanel from '@/features/contacts/components/ContactsPanel.vue'
import type { AddContactFeedback, ContactUser } from '@/features/contacts/contacts.contracts'
import { contactInitials, useContactsStore } from '@/features/contacts/contacts.store'
import ConversationListPanel from '@/features/conversations/components/ConversationListPanel.vue'
import GroupDetailsPanel from '@/features/conversations/components/GroupDetailsPanel.vue'
import NewGroupPanel from '@/features/conversations/components/NewGroupPanel.vue'
import type {
  ConversationRecord,
  GroupConversation,
  InboxConversationSummary,
} from '@/features/conversations/conversations.contracts'
import { type Conversation, conversations as mockConversations, type Message } from '@/features/conversations/conversations.mock'
import { useConversationsStore } from '@/features/conversations/conversations.store'
import ChatPanel from '@/features/messaging/components/ChatPanel.vue'
import type { PersistedMessage } from '@/features/messaging/messaging.contracts'
import { useMessagesStore, useMessagingStore } from '@/features/messaging/messaging.store'
import { useRealtimeMessaging } from '@/features/messaging/useRealtimeMessaging'
import { decodePresenceDiff, decodePresenceState, type PresenceStatus } from '@/features/presence/presence.contracts'
import { formatPresenceLabel } from '@/features/presence/presence.format'
import { useConversationSearch } from '@/features/search/useConversationSearch'
import { isApiError } from '@/shared/api/errors'
import { useAuthStore } from '@/stores/auth.store'

const selectedConversationId = ref<string | null>(null)
const router = useRouter()
const authStore = useAuthStore()
const contactsStore = useContactsStore()
const conversationsStore = useConversationsStore()
const messagingStore = useMessagingStore()
const messagesStore = useMessagesStore()
const { token } = storeToRefs(authStore)
const { user } = storeToRefs(authStore)
const { contactGroups, contacts, isEmpty, isLoading, loadError, pendingRemovalIds } = storeToRefs(contactsStore)
const {
  conversations: openedConversations,
  inboxSummaries,
  inboxLoadState,
  inboxLoadError,
  pendingPrivateUserIds,
  isSavingGroup,
  pendingMemberUserIds,
  pendingReadIds,
} = storeToRefs(conversationsStore)
const { historyByConversationId } = storeToRefs(messagesStore)
const sidebarMode = ref<'inbox' | 'new-group' | 'contacts' | 'group-details'>('inbox')
const isMobileListVisible = ref(true)
const isSearching = ref(false)
const isAddContactOpen = ref(false)
const isAddingContact = ref(false)
const inboxSearchQuery = ref('')
const searchTerm = ref('')
const messageDraft = ref('')
const groupName = ref('Squad Lancamento')
const groupError = ref<string | null>(null)
const selectedGroupContactIds = ref<Set<string>>(new Set())
const contactUsername = ref('')
const contactFeedback = ref<AddContactFeedback>({ kind: 'idle' })
const presenceByUserId = ref<Record<string, PresenceStatus>>({})
const currentUserId = computed(() => user.value?.id ?? null)
const emptyConversation: Conversation = {
  id: 'empty',
  type: 'private',
  initials: '--',
  name: 'Conversa',
  subtitle: '',
  preview: '',
  time: '',
  messages: [],
}
const selectedConversationIdRef = computed(() => selectedConversationId.value)
const activeConversationSearchQuery = computed(() => (isSearching.value ? searchTerm.value : ''))
const {
  activeHit: activeSearchHit,
  error: conversationSearchError,
  selectNext: selectNextSearchResult,
  selectPrevious: selectPreviousSearchResult,
  status: conversationSearchStatus,
  totalMatches: searchTotalMatches,
  truncated: searchTruncated,
} = useConversationSearch({
  token,
  conversationId: selectedConversationIdRef,
  query: activeConversationSearchQuery,
})
const {
  canSend: canSendMessage,
  error: realtimeError,
  sendMessage: sendRealtimeMessage,
} = useRealtimeMessaging({
  token,
  userId: currentUserId,
  selectedConversationId: selectedConversationIdRef,
  onPresenceState: applyPresenceState,
  onPresenceDiff: applyPresenceDiff,
  onConversationUpdated: conversationsStore.applyRealtimeUnread,
  onMembershipRevoked: handleMembershipRevoked,
  onReconnect: recoverAfterReconnect,
})

const searchActivePosition = computed(() => activeSearchHit.value?.position ?? null)
const searchActiveMessageId = computed(() => activeSearchHit.value?.message.id ?? null)
const searchActiveMatchOffsets = computed(() => activeSearchHit.value?.matchOffsets ?? [])

const selectedConversation = computed(() => {
  const conversation =
    conversationItems.value.find((item) => item.id === selectedConversationId.value) ??
    conversationItems.value[0] ??
    emptyConversation

  return withActiveSearchHit(conversation)
})

const conversationItems = computed(() => {
  if (!token.value) {
    return mockConversations.map(messagingStore.decorate)
  }

  const summaries = inboxSummaries.value.map(toInboxConversationItem).map(messagingStore.decorate)
  const openedItems = openedConversations.value
    .filter((conversation) => !summaries.some((summary) => summary.id === conversation.id))
    .map(toConversationItem)
    .map(messagingStore.decorate)

  return messagingStore.sortByActivity([...openedItems, ...summaries])
})

const isInboxLoading = computed(() => inboxLoadState.value === 'loading' && inboxSummaries.value.length === 0)
const isInboxEmpty = computed(
  () => Boolean(token.value) && inboxLoadState.value === 'success' && conversationItems.value.length === 0,
)

const selectedPersistedConversationId = computed(() => {
  const conversationId = selectedConversationId.value

  if (!conversationId) {
    return null
  }

  if (
    openedConversations.value.some((conversation) => conversation.id === conversationId) ||
    inboxSummaries.value.some((conversation) => conversation.id === conversationId)
  ) {
    return conversationId
  }

  return null
})
const selectedHistoryState = computed(() => {
  const history = historyByConversationId.value[selectedConversation.value.id]

  return (
    history ?? {
      messages: [],
      nextCursor: null,
      hasMore: false,
      isLoadingInitial: false,
      isLoadingOlder: false,
      didLoadInitial: false,
      error: null,
    }
  )
})
const selectedGroupConversation = computed<GroupConversation | null>(() => {
  const conversation = openedConversations.value.find(
    (item) => item.id === selectedConversationId.value && item.type === 'group',
  )

  return conversation?.type === 'group' ? conversation : null
})

watch(
  token,
  (currentToken, _previousToken, onCleanup) => {
    if (!currentToken) {
      contactsStore.reset()
      conversationsStore.reset()
      messagesStore.reset()
      return
    }

    const controller = new AbortController()
    contactsStore.load(currentToken, controller.signal)
    onCleanup(() => controller.abort())
  },
  { immediate: true },
)

watch(
  [token, inboxSearchQuery],
  ([currentToken, currentSearchQuery], _previous, onCleanup) => {
    if (!currentToken) {
      return
    }

    const controller = new AbortController()
    conversationsStore.loadInbox(currentToken, controller.signal, currentSearchQuery)
    onCleanup(() => controller.abort())
  },
  { immediate: true },
)

watch(
  [conversationItems, token],
  ([items, currentToken]) => {
    if (!currentToken || items.length === 0) {
      return
    }

    if (!items.some((item) => item.id === selectedConversationId.value)) {
      selectedConversationId.value = items[0].id
    }
  },
  { immediate: true },
)

async function selectConversation(conversationId: string) {
  selectedConversationId.value = conversationId
  isMobileListVisible.value = false

  const currentToken = token.value
  const summary = inboxSummaries.value.find((conversation) => conversation.id === conversationId)

  if (!currentToken || !summary || summary.unreadCount === 0 || pendingReadIds.value.has(conversationId)) {
    return
  }

  try {
    await conversationsStore.markRead(conversationId, currentToken)
  } catch (error) {
    inboxLoadError.value = conversationErrorMessage(error)
  }
}

watch(
  [selectedPersistedConversationId, token],
  ([conversationId, currentToken], _previous, onCleanup) => {
    if (!conversationId || !currentToken) {
      return
    }

    const controller = new AbortController()
    messagesStore.loadInitial(conversationId, currentToken, controller.signal)
    onCleanup(() => controller.abort())
  },
  { immediate: true },
)

function openSearch() {
  searchTerm.value = ''
  isSearching.value = true
}

function closeSearch() {
  isSearching.value = false
  searchTerm.value = ''
}

function closeSearchOnFocusOut(event: FocusEvent) {
  const nextTarget = event.relatedTarget

  if (nextTarget instanceof Node && event.currentTarget instanceof Node) {
    if (event.currentTarget.contains(nextTarget)) {
      return
    }
  }

  closeSearch()
}

function showMobileConversationList(): void {
  isMobileListVisible.value = true
  sidebarMode.value = 'inbox'
}

function sendMessage() {
  const body = messageDraft.value.trim()

  if (!body) {
    return
  }

  if (!sendRealtimeMessage(body)) {
    return
  }

  messageDraft.value = ''
}

function recoverAfterReconnect(): void {
  const currentToken = token.value

  if (!currentToken) {
    return
  }

  void conversationsStore.loadInbox(currentToken, undefined, inboxSearchQuery.value)

  if (selectedPersistedConversationId.value) {
    void messagesStore.loadInitial(selectedPersistedConversationId.value, currentToken, undefined, {
      force: true,
      silent: true,
    })
  }
}

function loadOlderMessages() {
  const currentToken = token.value

  if (!currentToken) {
    return
  }

  messagesStore.loadOlder(selectedConversation.value.id, currentToken)
}

function logout() {
  contactsStore.reset()
  conversationsStore.reset()
  messagingStore.reset()
  messagesStore.reset()
  authStore.logout()
  router.push('/')
}

function toggleGroupContact(userId: string) {
  const nextIds = new Set(selectedGroupContactIds.value)

  if (nextIds.has(userId)) {
    nextIds.delete(userId)
  } else {
    nextIds.add(userId)
  }

  selectedGroupContactIds.value = nextIds
}

async function createGroup() {
  const currentToken = token.value

  if (!currentToken || isSavingGroup.value) {
    return
  }

  if (!groupName.value.trim()) {
    groupError.value = 'Informe o nome do grupo.'
    return
  }

  if (selectedGroupContactIds.value.size === 0) {
    groupError.value = 'Selecione pelo menos um contato.'
    return
  }

  groupError.value = null

  try {
    const conversation = await conversationsStore.createGroup(
      groupName.value,
      Array.from(selectedGroupContactIds.value),
      currentToken,
    )
    selectedConversationId.value = conversation.id
    isMobileListVisible.value = false
    selectedGroupContactIds.value = new Set()
    groupName.value = ''
    sidebarMode.value = 'inbox'
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

async function openGroupDetails() {
  const currentToken = token.value
  const selectedGroup = selectedGroupConversation.value

  if (selectedGroup) {
    groupError.value = null
    sidebarMode.value = 'group-details'
    isMobileListVisible.value = true
    return
  }

  if (!currentToken || selectedConversation.value.type !== 'group') {
    return
  }

  try {
    await conversationsStore.loadConversation(selectedConversation.value.id, currentToken)
    groupError.value = null
    sidebarMode.value = 'group-details'
    isMobileListVisible.value = true
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

async function addGroupMember(userId: string) {
  const currentToken = token.value
  const group = selectedGroupConversation.value

  if (!currentToken || !group) {
    return
  }

  try {
    await conversationsStore.addMembers(group.id, [userId], currentToken)
    groupError.value = null
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

async function removeGroupMember(userId: string) {
  const currentToken = token.value
  const group = selectedGroupConversation.value

  if (!currentToken || !group) {
    return
  }

  try {
    await conversationsStore.removeMember(group.id, userId, currentToken)
    groupError.value = null
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

async function leaveSelectedGroup() {
  const currentToken = token.value
  const userId = currentUserId.value
  const group = selectedGroupConversation.value

  if (!currentToken || !userId || !group) {
    return
  }

  try {
    await conversationsStore.leave(group.id, currentToken)
    removeConversationCaches(group.id)
    sidebarMode.value = 'inbox'
    selectedConversationId.value = conversationItems.value[0]?.id ?? null
    groupError.value = null
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

function handleMembershipRevoked(conversationId: string): void {
  removeConversationCaches(conversationId)
  sidebarMode.value = 'inbox'
  isMobileListVisible.value = true

  if (selectedConversationId.value === conversationId) {
    selectedConversationId.value = conversationItems.value.find((conversation) => conversation.id !== conversationId)?.id ?? null
  }
}

function removeConversationCaches(conversationId: string): void {
  conversationsStore.removeConversation(conversationId)
  messagesStore.removeConversation(conversationId)
  messagingStore.removeConversation(conversationId)
}

async function openPrivateConversation(userId: string) {
  const currentToken = token.value

  if (!currentToken) {
    return
  }

  try {
    const conversation = await conversationsStore.openPrivate(userId, currentToken)
    selectedConversationId.value = conversation.id
    isMobileListVisible.value = false
    sidebarMode.value = 'inbox'
  } catch (error) {
    loadError.value = conversationErrorMessage(error)
  }
}

function openAddContact() {
  contactUsername.value = ''
  contactFeedback.value = { kind: 'idle' }
  isAddContactOpen.value = true
}

function closeAddContact() {
  isAddContactOpen.value = false
}

async function addContact() {
  const currentToken = token.value

  if (!contactUsername.value) {
    contactFeedback.value = {
      kind: 'error',
      title: 'Usuario obrigatorio',
      message: 'Informe o @usuario que deseja adicionar.',
    }
    return
  }

  if (!currentToken || isAddingContact.value) {
    return
  }

  isAddingContact.value = true
  contactFeedback.value = { kind: 'idle' }

  try {
    const contact = await contactsStore.add(contactUsername.value, currentToken)
    contactFeedback.value = {
      kind: 'success',
      message: `${contact.user.name} (@${contact.user.username}) entrou na sua lista.`,
    }
    contactUsername.value = ''
  } catch (error) {
    contactFeedback.value = contactErrorFeedback(error)
  } finally {
    isAddingContact.value = false
  }
}

async function removeContact(contactId: string) {
  const currentToken = token.value

  if (!currentToken) {
    return
  }

  try {
    await contactsStore.remove(contactId, currentToken)
  } catch {
    loadError.value = 'Não foi possível remover o contato.'
  }
}

function contactErrorFeedback(error: unknown): AddContactFeedback {
  if (isApiError(error)) {
    if (error.code === 'user_not_found') {
      return {
        kind: 'error',
        title: 'Usuario nao encontrado',
        message: error.message,
      }
    }

    if (error.code === 'contact_already_exists') {
      return {
        kind: 'error',
        title: 'Contato ja adicionado',
        message: error.message,
      }
    }

    if (error.code === 'self_contact') {
      return {
        kind: 'error',
        title: 'Este e voce',
        message: error.message,
      }
    }
  }

  return {
    kind: 'error',
    title: 'Nao foi possivel adicionar',
    message: error instanceof Error ? error.message : 'Tente novamente em instantes.',
  }
}

function conversationErrorMessage(error: unknown): string {
  if (isApiError(error)) {
    return error.message
  }

  return error instanceof Error ? error.message : 'Não foi possível atualizar a conversa.'
}

function toConversationItem(conversation: ConversationRecord) {
  const messages = historyByConversationId.value[conversation.id]?.messages.map(toMessageItem) ?? []

  if (conversation.type === 'private') {
    return {
      id: conversation.id,
      type: conversation.type,
      initials: contactInitials(conversation.counterpart.name),
      name: conversation.counterpart.name,
      subtitle: presenceSubtitle(conversation.counterpart),
      preview: 'Conversa iniciada',
      time: '',
      messages,
    }
  }

  return {
    id: conversation.id,
    type: conversation.type,
    initials: contactInitials(conversation.name),
    name: conversation.name,
    subtitle: `${conversation.memberCount} membros`,
    preview: 'Grupo criado',
    time: '',
    messages,
  }
}

function toInboxConversationItem(conversation: InboxConversationSummary): Conversation & { unreadLabel?: string } {
  const messages = historyByConversationId.value[conversation.id]?.messages.map(toMessageItem) ?? []

  return {
    id: conversation.id,
    type: conversation.type,
    initials: contactInitials(conversation.title),
    name: conversation.title,
    subtitle:
      conversation.type === 'group'
        ? `${conversation.memberCount ?? 0} membros`
        : conversation.counterpart
          ? presenceSubtitle(conversation.counterpart)
          : 'offline',
    preview: inboxPreview(conversation),
    time: conversation.lastMessage ? formatMessageTime(conversation.lastMessage.insertedAt) : '',
    messages,
    unreadLabel: unreadLabel(conversation),
  }
}

function inboxPreview(conversation: InboxConversationSummary): string {
  const message = conversation.lastMessage

  if (!message) {
    return 'Nenhuma mensagem'
  }

  const prefix = message.senderId === currentUserId.value ? 'Voce: ' : ''

  return `${prefix}${message.body}`
}

function unreadLabel(conversation: InboxConversationSummary): string | undefined {
  if (conversation.unreadCount <= 0) {
    return undefined
  }

  return conversation.unreadOverflow ? '99+' : String(conversation.unreadCount)
}

function applyPresenceState(payload: unknown): void {
  applyPresenceUpdates(decodePresenceState(payload))
}

function applyPresenceDiff(payload: unknown): void {
  applyPresenceUpdates(decodePresenceDiff(payload))
}

function applyPresenceUpdates(updates: PresenceStatus[]): void {
  const nextPresence = { ...presenceByUserId.value }

  for (const update of updates) {
    nextPresence[update.userId] = update
  }

  presenceByUserId.value = nextPresence
}

function presenceSubtitle(user: ContactUser): string {
  const status = presenceByUserId.value[user.id] ?? {
    userId: user.id,
    online: user.online,
    lastSeenAt: user.lastSeenAt,
  }

  return formatPresenceLabel(status)
}

function toMessageItem(message: PersistedMessage): Message {
  return {
    id: message.id,
    side: message.sender.id === currentUserId.value ? 'out' : 'in',
    author: message.sender.id === currentUserId.value ? undefined : message.sender.name,
    text: message.body,
    time: formatMessageTime(message.insertedAt),
    wide: message.body.length > 44,
  }
}

function withActiveSearchHit(conversation: Conversation): Conversation {
  const hit = activeSearchHit.value

  if (!hit || hit.message.conversationId !== conversation.id) {
    return conversation
  }

  if (conversation.messages.some((message) => message.id === hit.message.id)) {
    return conversation
  }

  return {
    ...conversation,
    messages: [...conversation.messages, toMessageItem(hit.message)],
  }
}

function formatMessageTime(value: string): string {
  const date = new Date(value)

  if (Number.isNaN(date.getTime())) {
    return ''
  }

  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  }).format(date)
}
</script>
