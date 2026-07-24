import { readonly, ref, toValue, type MaybeRefOrGetter } from 'vue'

import { isApiError } from '@/shared/api/errors'

import type { AddContactFeedback } from './contacts.contracts'
import { useContactsStore } from './contacts.store'

interface UseAddContactDialogOptions {
  token: MaybeRefOrGetter<string | null>
}

export function useAddContactDialog({ token }: UseAddContactDialogOptions) {
  const contactsStore = useContactsStore()
  const isOpen = ref(false)
  const isSubmitting = ref(false)
  const username = ref('')
  const feedback = ref<AddContactFeedback>({ kind: 'idle' })

  function open(): void {
    username.value = ''
    feedback.value = { kind: 'idle' }
    isOpen.value = true
  }

  function close(): void {
    isOpen.value = false
  }

  async function submit(): Promise<void> {
    const currentToken = toValue(token)

    if (!username.value) {
      feedback.value = {
        kind: 'error',
        title: 'Usuario obrigatorio',
        message: 'Informe o @usuario que deseja adicionar.',
      }
      return
    }

    if (!currentToken || isSubmitting.value) {
      return
    }

    isSubmitting.value = true
    feedback.value = { kind: 'idle' }

    try {
      const contact = await contactsStore.add(username.value, currentToken)
      feedback.value = {
        kind: 'success',
        message: `${contact.user.name} (@${contact.user.username}) entrou na sua lista.`,
      }
      username.value = ''
    } catch (error) {
      feedback.value = contactErrorFeedback(error)
    } finally {
      isSubmitting.value = false
    }
  }

  return {
    isOpen: readonly(isOpen),
    isSubmitting: readonly(isSubmitting),
    username,
    feedback: readonly(feedback),
    open,
    close,
    submit,
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
