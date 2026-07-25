<template>
  <section class="grid h-full grid-rows-[64px_auto_minmax(0,1fr)_auto] bg-white">
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
        <strong class="block truncate text-[18px] text-[#171717]">{{ group.name }}</strong>
        <span class="block text-[13px] text-[#a3a3a3]">{{ group.memberCount }} membros</span>
      </div>
    </header>

    <p
      v-if="error"
      class="m-3 rounded-lg border border-[#fecaca] bg-[#fef2f2] p-3 text-[13px] text-[#dc2626]"
      role="alert"
    >
      {{ error }}
    </p>

    <div class="min-h-0 overflow-auto px-3 py-4">
      <div class="mb-2 text-[12px] font-bold uppercase text-[#a3a3a3]">Membros</div>
      <div
        v-for="member in group.members"
        :key="member.id"
        class="grid min-h-[56px] grid-cols-[40px_minmax(0,1fr)_34px] items-center gap-3"
      >
        <span
          class="grid h-9 w-9 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[12px] font-bold text-[#444444]"
        >
          {{ userInitials(member.name) }}
        </span>
        <span class="min-w-0">
          <strong class="block truncate text-[14px] text-[#171717]">{{ member.name }}</strong>
          <span class="block truncate text-[12px] text-[#a3a3a3]">@{{ member.username }}</span>
        </span>
        <button
          v-if="canManage && member.id !== currentUserId"
          class="grid h-8 w-8 place-items-center rounded-lg border border-[#e8e8e8] bg-white text-[#737373] hover:bg-[#f5f5f5]"
          type="button"
          :aria-label="`Remover ${member.name}`"
          :disabled="pendingUserIds.has(member.id)"
          @click="$emit('removeMember', member.id)"
        >
          <Trash2 :size="16" :stroke-width="2" aria-hidden="true" />
        </button>
      </div>

      <template v-if="canManage && addableContacts.length > 0">
        <div class="mb-2 mt-5 text-[12px] font-bold uppercase text-[#a3a3a3]">Adicionar contatos</div>
        <button
          v-for="contact in addableContacts"
          :key="contact.id"
          class="grid min-h-[52px] w-full grid-cols-[40px_minmax(0,1fr)_34px] items-center gap-3 text-left"
          type="button"
          :disabled="pendingUserIds.has(contact.user.id)"
          @click="$emit('addMember', contact.user.id)"
        >
          <span
            class="grid h-9 w-9 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[12px] font-bold text-[#444444]"
          >
            {{ userInitials(contact.user.name) }}
          </span>
          <span class="min-w-0">
            <strong class="block truncate text-[14px] text-[#171717]">{{ contact.user.name }}</strong>
            <span class="block truncate text-[12px] text-[#a3a3a3]">@{{ contact.user.username }}</span>
          </span>
          <Plus :size="17" :stroke-width="2" aria-hidden="true" />
        </button>
      </template>
    </div>

    <footer class="border-t border-[#e8e8e8] p-3">
      <button
        class="h-10 w-full rounded-lg border border-[#fecaca] bg-white text-[14px] font-bold text-[#dc2626] hover:bg-[#fef2f2]"
        type="button"
        @click="$emit('leaveGroup')"
      >
        Sair do grupo
      </button>
    </footer>
  </section>
</template>

<script setup lang="ts">
import { ArrowLeft, Plus, Trash2 } from '@lucide/vue'
import { computed } from 'vue'

import { userInitials } from '@/shared/user/userInitials'
import type { Contact } from '@/types/contact'

import type { GroupConversation } from '../conversations.contracts'

const props = defineProps<{
  contacts: Contact[]
  currentUserId: string
  error: string | null
  group: GroupConversation
  pendingUserIds: Set<string>
}>()

const canManage = computed(() => props.group.creatorId === props.currentUserId)
const activeMemberIds = computed(() => new Set(props.group.members.map((member) => member.id)))
const addableContacts = computed(() =>
  props.contacts.filter((contact) => !activeMemberIds.value.has(contact.user.id)),
)

defineEmits<{
  addMember: [userId: string]
  close: []
  leaveGroup: []
  removeMember: [userId: string]
}>()
</script>
