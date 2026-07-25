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
import { useContactsStore } from '@/features/contacts/contacts.store'
import { useAddContactDialog } from '@/features/contacts/useAddContactDialog'
import ConversationListPanel from '@/features/conversations/components/ConversationListPanel.vue'
import GroupDetailsPanel from '@/features/conversations/components/GroupDetailsPanel.vue'
import NewGroupPanel from '@/features/conversations/components/NewGroupPanel.vue'
import { conversationErrorMessage } from '@/features/conversations/conversations.error'
import { useConversationsStore } from '@/features/conversations/conversations.store'
import { useCreateGroup } from '@/features/conversations/useCreateGroup'
import { useGroupDetails } from '@/features/conversations/useGroupDetails'
import { useInboxList } from '@/features/conversations/useInboxList'
import ChatPanel from '@/features/messaging/components/ChatPanel.vue'
import { useMessagesStore, useMessagingStore } from '@/features/messaging/messaging.store'
import { useConversationHistory } from '@/features/messaging/useConversationHistory'
import { useMessageComposer } from '@/features/messaging/useMessageComposer'
import { useRealtimeMessaging } from '@/features/messaging/useRealtimeMessaging'
import { useConversationPresence } from '@/features/presence/useConversationPresence'
import { useConversationSearchPanel } from '@/features/search/useConversationSearchPanel'
import { userInitials } from '@/shared/user/userInitials'
import { useAuthStore } from '@/stores/auth.store'
import type { ChatConversation } from '@/types/chat'
import {
  toConversationItem,
  toInboxConversationItem,
  withActiveSearchHit,
} from '@/views/inbox/inbox.presenter'
import { useInboxRouteState } from '@/views/inbox/useInboxRouteState'

const router = useRouter()
const { inboxSearchQuery, selectedConversationId } = useInboxRouteState()
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
  pendingPrivateUserIds,
  pendingMemberUserIds,
} = storeToRefs(conversationsStore)
const { histories } = storeToRefs(messagesStore)
const sidebarMode = ref<'inbox' | 'new-group' | 'contacts' | 'group-details'>('inbox')
const isMobileListVisible = ref(true)
const groupError = ref<string | null>(null)
const currentUserId = computed(() => user.value?.id ?? null)
const {
  close: closeAddContact,
  feedback: contactFeedback,
  isOpen: isAddContactOpen,
  isSubmitting: isAddingContact,
  open: openAddContact,
  submit: addContact,
  username: contactUsername,
} = useAddContactDialog({ token })
const {
  isSubmitting: isSavingGroup,
  name: groupName,
  selectedContactIds: selectedGroupContactIds,
  submit: submitGroup,
  toggleContact: toggleGroupContact,
} = useCreateGroup({ token, error: groupError })
const {
  addMember: addGroupMember,
  leave: leaveGroup,
  open: openSelectedGroupDetails,
  removeMember: removeGroupMember,
  selectedGroupConversation,
} = useGroupDetails({
  token,
  currentUserId,
  selectedConversationId,
  error: groupError,
})
const {
  applyDiff: applyPresenceDiff,
  applyState: applyPresenceState,
  subtitleFor: presenceSubtitle,
} = useConversationPresence()
const emptyConversation: ChatConversation = {
  id: 'empty',
  type: 'private',
  initials: '--',
  name: 'Conversa',
  subtitle: '',
  preview: '',
  time: '',
  messages: [],
}
const {
  activeHit: activeSearchHit,
  activeMatchOffsets: searchActiveMatchOffsets,
  activeMessageId: searchActiveMessageId,
  activePosition: searchActivePosition,
  close: closeSearch,
  closeOnFocusOut: closeSearchOnFocusOut,
  error: conversationSearchError,
  isOpen: isSearching,
  open: openSearch,
  selectNext: selectNextSearchResult,
  selectPrevious: selectPreviousSearchResult,
  status: conversationSearchStatus,
  term: searchTerm,
  totalMatches: searchTotalMatches,
  truncated: searchTruncated,
} = useConversationSearchPanel({
  token,
  conversationId: selectedConversationId,
})
const {
  canSend: canSendMessage,
  error: realtimeError,
  sendMessage: sendRealtimeMessage,
} = useRealtimeMessaging({
  token,
  userId: currentUserId,
  selectedConversationId,
  onPresenceState: applyPresenceState,
  onPresenceDiff: applyPresenceDiff,
  onConversationUpdated: handleConversationUpdated,
  onMembershipRevoked: handleMembershipRevoked,
  onReconnect: recoverAfterReconnect,
})
const {
  draft: messageDraft,
  submit: sendMessage,
} = useMessageComposer({ send: sendRealtimeMessage })

const selectedConversation = computed(() => {
  const conversation =
    conversationItems.value.find((item) => item.id === selectedConversationId.value) ??
    conversationItems.value[0] ??
    emptyConversation

  return withActiveSearchHit(conversation, activeSearchHit.value, currentUserId.value)
})

const conversationItems = computed(() => {
  const presenterContext = {
    currentUserId: currentUserId.value,
    histories: histories.value,
    initialsFor: userInitials,
    presenceSubtitleFor: presenceSubtitle,
  }
  const summaries = inboxSummaries.value
    .map((conversation) => toInboxConversationItem(conversation, presenterContext))
    .map(messagingStore.decorate)
  const openedItems = openedConversations.value
    .filter((conversation) => !summaries.some((summary) => summary.id === conversation.id))
    .map((conversation) => toConversationItem(conversation, presenterContext))
    .map(messagingStore.decorate)

  return messagingStore.sortByActivity([...openedItems, ...summaries])
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

const {
  error: inboxLoadError,
  isEmpty: isInboxEmpty,
  isLoading: isInboxLoading,
  acknowledgeRealtimeRead,
  reload: reloadInbox,
  select: selectInboxConversation,
} = useInboxList({
  token,
  items: conversationItems,
  selectedConversationId,
  query: inboxSearchQuery,
})
const displayedConversationId = computed(() => selectedConversation.value.id)
const {
  state: selectedHistoryState,
  loadOlder: loadOlderMessages,
  refresh: refreshConversationHistory,
} = useConversationHistory({
  token,
  selectedConversationId,
  displayedConversationId,
  persistedConversationSources: [openedConversations, inboxSummaries],
})

async function selectConversation(conversationId: string) {
  const selection = selectInboxConversation(conversationId)
  isMobileListVisible.value = false
  await selection
}

function showMobileConversationList(): void {
  isMobileListVisible.value = true
  sidebarMode.value = 'inbox'
}

function recoverAfterReconnect(): void {
  const currentToken = token.value

  if (!currentToken) {
    return
  }

  void reloadInbox()
  refreshConversationHistory()
}

function handleConversationUpdated(update: Parameters<typeof conversationsStore.applyRealtimeUnread>[0]): void {
  if (update.conversationId !== selectedConversationId.value) {
    conversationsStore.applyRealtimeUnread(update)
    return
  }

  conversationsStore.applyRealtimeUnread({ ...update, unread: false })

  if (update.unread) {
    void acknowledgeRealtimeRead(update.conversationId)
  }
}

function logout() {
  contactsStore.reset()
  conversationsStore.reset()
  messagingStore.reset()
  messagesStore.reset()
  authStore.logout({ revoke: true })
  router.push('/')
}

async function createGroup() {
  const conversation = await submitGroup()

  if (!conversation) {
    return
  }

  selectedConversationId.value = conversation.id
  isMobileListVisible.value = false
  sidebarMode.value = 'inbox'
}

async function openGroupDetails() {
  const didOpen = await openSelectedGroupDetails(
    selectedConversation.value.id,
    selectedConversation.value.type,
  )

  if (!didOpen) {
    return
  }

  sidebarMode.value = 'group-details'
  isMobileListVisible.value = true
}

async function leaveSelectedGroup() {
  const conversationId = await leaveGroup()

  if (!conversationId) {
    return
  }

  removeConversationCaches(conversationId)
  sidebarMode.value = 'inbox'
  selectedConversationId.value = conversationItems.value[0]?.id ?? null
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

</script>
