<template>
  <main class="h-full bg-[#f7f7f7]">
    <div
      class="grid h-full overflow-hidden bg-white min-[860px]:grid-cols-[418px_minmax(0,1fr)]"
    >
      <aside class="border-r border-[#e8e8e8] bg-white max-[859px]:hidden">
        <ConversationListPanel
          v-if="sidebarMode === 'inbox'"
          :conversations="conversationItems"
          :error="inboxLoadError"
          :is-empty="isInboxEmpty"
          :is-loading="isInboxLoading"
          :selected-conversation-id="selectedConversationId"
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
        :conversation="selectedConversation"
        :is-searching="isSearching"
        @close-search="isSearching = false"
        @open-group-details="openGroupDetails"
        @open-search="openSearch"
        @search-focusout="closeSearchOnFocusOut"
        @send-message="sendMessage"
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
import type { AddContactFeedback } from '@/features/contacts/contacts.contracts'
import { contactInitials, useContactsStore } from '@/features/contacts/contacts.store'
import ConversationListPanel from '@/features/conversations/components/ConversationListPanel.vue'
import GroupDetailsPanel from '@/features/conversations/components/GroupDetailsPanel.vue'
import NewGroupPanel from '@/features/conversations/components/NewGroupPanel.vue'
import type {
  ConversationRecord,
  GroupConversation,
  InboxConversationSummary,
} from '@/features/conversations/conversations.contracts'
import { type Conversation, conversations } from '@/features/conversations/conversations.mock'
import { useConversationsStore } from '@/features/conversations/conversations.store'
import ChatPanel from '@/features/messaging/components/ChatPanel.vue'
import { isApiError } from '@/shared/api/errors'
import { useAuthStore } from '@/stores/auth.store'

const selectedConversationId = ref('ana')
const router = useRouter()
const authStore = useAuthStore()
const contactsStore = useContactsStore()
const conversationsStore = useConversationsStore()
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
const sidebarMode = ref<'inbox' | 'new-group' | 'contacts' | 'group-details'>('inbox')
const isSearching = ref(false)
const isAddContactOpen = ref(false)
const isAddingContact = ref(false)
const searchTerm = ref('')
const messageDraft = ref('')
const groupName = ref('Squad Lancamento')
const groupError = ref<string | null>(null)
const selectedGroupContactIds = ref<Set<string>>(new Set())
const contactUsername = ref('')
const contactFeedback = ref<AddContactFeedback>({ kind: 'idle' })
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

const selectedConversation = computed(
  () =>
    conversationItems.value.find((conversation) => conversation.id === selectedConversationId.value) ??
    conversationItems.value[0] ??
    emptyConversation,
)

const conversationItems = computed(() => {
  if (!token.value) {
    return conversations
  }

  const summaries = inboxSummaries.value.map(toInboxConversationItem)
  const openedItems = openedConversations.value
    .filter((conversation) => !summaries.some((summary) => summary.id === conversation.id))
    .map(toConversationItem)

  return [...openedItems, ...summaries]
})

const isInboxLoading = computed(() => inboxLoadState.value === 'loading' && inboxSummaries.value.length === 0)
const isInboxEmpty = computed(
  () => Boolean(token.value) && inboxLoadState.value === 'success' && conversationItems.value.length === 0,
)

const currentUserId = computed(() => user.value?.id ?? null)
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
      return
    }

    const controller = new AbortController()
    contactsStore.load(currentToken, controller.signal)
    conversationsStore.loadInbox(currentToken, controller.signal)
    onCleanup(() => controller.abort())
  },
  { immediate: true },
)

async function selectConversation(conversationId: string) {
  selectedConversationId.value = conversationId

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
  contactsStore.reset()
  conversationsStore.reset()
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
    selectedGroupContactIds.value = new Set()
    groupName.value = ''
    sidebarMode.value = 'inbox'
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

function openGroupDetails() {
  if (selectedGroupConversation.value) {
    groupError.value = null
    sidebarMode.value = 'group-details'
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
    await conversationsStore.leave(group.id, userId, currentToken)
    sidebarMode.value = 'inbox'
    selectedConversationId.value = conversations[0].id
    groupError.value = null
  } catch (error) {
    groupError.value = conversationErrorMessage(error)
  }
}

async function openPrivateConversation(userId: string) {
  const currentToken = token.value

  if (!currentToken) {
    return
  }

  try {
    const conversation = await conversationsStore.openPrivate(userId, currentToken)
    selectedConversationId.value = conversation.id
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
  if (conversation.type === 'private') {
    return {
      id: conversation.id,
      type: conversation.type,
      initials: contactInitials(conversation.counterpart.name),
      name: conversation.counterpart.name,
      subtitle: conversation.counterpart.lastSeenAt ? 'visto recentemente' : 'offline',
      preview: 'Conversa iniciada',
      time: '',
      messages: [],
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
    messages: [],
  }
}

function toInboxConversationItem(conversation: InboxConversationSummary): Conversation & { unreadLabel?: string } {
  return {
    id: conversation.id,
    type: conversation.type,
    initials: contactInitials(conversation.title),
    name: conversation.title,
    subtitle:
      conversation.type === 'group'
        ? `${conversation.memberCount ?? 0} membros`
        : conversation.counterpart?.lastSeenAt
          ? 'visto recentemente'
          : 'offline',
    preview: inboxPreview(conversation),
    time: conversation.lastMessage ? formatConversationTime(conversation.lastMessage.insertedAt) : '',
    messages: [],
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

function formatConversationTime(value: string): string {
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
