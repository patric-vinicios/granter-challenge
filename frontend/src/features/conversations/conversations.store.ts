import { defineStore } from 'pinia'
import { ref } from 'vue'

import {
  addGroupMembers,
  createGroupConversation,
  leaveGroup,
  openPrivateConversation as openPrivateConversationRequest,
  removeGroupMember,
} from './conversations.api'
import type { ConversationRecord } from './conversations.contracts'

export const useConversationsStore = defineStore('conversations', () => {
  const conversations = ref<ConversationRecord[]>([])
  const pendingPrivateUserIds = ref<Set<string>>(new Set())
  const isSavingGroup = ref(false)
  const pendingMemberUserIds = ref<Set<string>>(new Set())

  async function openPrivate(userId: string, token: string): Promise<ConversationRecord> {
    pendingPrivateUserIds.value = new Set(pendingPrivateUserIds.value).add(userId)

    try {
      const conversation = await openPrivateConversationRequest(userId, token)
      upsertConversation(conversation)

      return conversation
    } finally {
      const nextIds = new Set(pendingPrivateUserIds.value)
      nextIds.delete(userId)
      pendingPrivateUserIds.value = nextIds
    }
  }

  async function createGroup(name: string, memberIds: string[], token: string): Promise<ConversationRecord> {
    isSavingGroup.value = true

    try {
      const conversation = await createGroupConversation(name, memberIds, token)
      upsertConversation(conversation)

      return conversation
    } finally {
      isSavingGroup.value = false
    }
  }

  async function addMembers(conversationId: string, memberIds: string[], token: string): Promise<ConversationRecord> {
    pendingMemberUserIds.value = new Set([...pendingMemberUserIds.value, ...memberIds])

    try {
      const conversation = await addGroupMembers(conversationId, memberIds, token)
      upsertConversation(conversation)

      return conversation
    } finally {
      clearPending(memberIds)
    }
  }

  async function removeMember(conversationId: string, userId: string, token: string): Promise<void> {
    pendingMemberUserIds.value = new Set(pendingMemberUserIds.value).add(userId)

    try {
      await removeGroupMember(conversationId, userId, token)
      removeMemberLocally(conversationId, userId)
    } finally {
      clearPending([userId])
    }
  }

  async function leave(conversationId: string, currentUserId: string, token: string): Promise<void> {
    await leaveGroup(conversationId, token)
    removeMemberLocally(conversationId, currentUserId)
  }

  function reset(): void {
    conversations.value = []
    pendingPrivateUserIds.value = new Set()
    isSavingGroup.value = false
    pendingMemberUserIds.value = new Set()
  }

  function upsertConversation(conversation: ConversationRecord): void {
    const index = conversations.value.findIndex((item) => item.id === conversation.id)

    if (index >= 0) {
      const nextConversations = [...conversations.value]
      nextConversations[index] = conversation
      conversations.value = nextConversations
      return
    }

    conversations.value = [conversation, ...conversations.value]
  }

  function removeMemberLocally(conversationId: string, userId: string): void {
    conversations.value = conversations.value.map((conversation) => {
      if (conversation.id !== conversationId || conversation.type !== 'group') {
        return conversation
      }

      const members = conversation.members.filter((member) => member.id !== userId)

      return { ...conversation, members, memberCount: members.length }
    })
  }

  function clearPending(userIds: string[]): void {
    const nextIds = new Set(pendingMemberUserIds.value)

    for (const userId of userIds) {
      nextIds.delete(userId)
    }

    pendingMemberUserIds.value = nextIds
  }

  return {
    conversations,
    pendingPrivateUserIds,
    isSavingGroup,
    pendingMemberUserIds,
    openPrivate,
    createGroup,
    addMembers,
    removeMember,
    leave,
    reset,
  }
})
