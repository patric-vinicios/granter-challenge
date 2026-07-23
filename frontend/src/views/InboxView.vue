<template>
  <main class="h-full bg-[#f7f7f7]">
    <div
      class="grid h-full overflow-hidden bg-white min-[860px]:grid-cols-[418px_minmax(0,1fr)]"
    >
      <aside class="border-r border-[#e8e8e8] bg-white max-[859px]:hidden">
        <ConversationListPanel
          v-if="sidebarMode === 'inbox'"
          :conversations="conversations"
          :selected-conversation-id="selectedConversationId"
          @create-group="sidebarMode = 'new-group'"
          @open-contacts="sidebarMode = 'contacts'"
          @logout="logout"
          @select-conversation="selectedConversationId = $event"
        />

        <ContactsPanel
          v-else-if="sidebarMode === 'contacts'"
          :contact-groups="contactGroups"
          @add-contact="openAddContact"
          @close="sidebarMode = 'inbox'"
        />

        <NewGroupPanel
          v-else
          v-model:group-name="groupName"
          :contacts="groupContacts"
          :selected-contacts="selectedGroupContacts"
          @close="sidebarMode = 'inbox'"
        />
      </aside>

      <ChatPanel
        v-model:message-draft="messageDraft"
        v-model:search-term="searchTerm"
        :conversation="selectedConversation"
        :is-searching="isSearching"
        @close-search="isSearching = false"
        @open-search="openSearch"
        @search-focusout="closeSearchOnFocusOut"
        @send-message="sendMessage"
      />
    </div>

    <AddContactDialog
      v-if="isAddContactOpen"
      v-model:username="contactUsername"
      :feedback="contactFeedback"
      @add-contact="addContact"
      @close="closeAddContact"
    />
  </main>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'

import AddContactDialog from '@/features/contacts/components/AddContactDialog.vue'
import ContactsPanel from '@/features/contacts/components/ContactsPanel.vue'
import { contactGroups, groupContacts } from '@/features/contacts/contacts.mock'
import ConversationListPanel from '@/features/conversations/components/ConversationListPanel.vue'
import { conversations } from '@/features/conversations/conversations.mock'
import NewGroupPanel from '@/features/conversations/components/NewGroupPanel.vue'
import ChatPanel from '@/features/messaging/components/ChatPanel.vue'

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
