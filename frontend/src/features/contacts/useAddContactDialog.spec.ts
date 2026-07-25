import { createPinia, setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { ApiError } from '@/shared/api/errors'
import { deferred } from '@/test/http'

import type { Contact } from './contacts.contracts'
import { useContactsStore } from './contacts.store'
import { useAddContactDialog } from './useAddContactDialog'

describe('useAddContactDialog', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('resets stale form state whenever the dialog opens', async () => {
    const dialog = useAddContactDialog({ token: 'jwt-token' })
    dialog.username.value = '@ana'
    await dialog.submit()

    dialog.open()

    expect(dialog.isOpen.value).toBe(true)
    expect(dialog.username.value).toBe('')
    expect(dialog.feedback.value).toEqual({ kind: 'idle' })

    dialog.close()
    expect(dialog.isOpen.value).toBe(false)
  })

  it('requires a username before submitting', async () => {
    const dialog = useAddContactDialog({ token: 'jwt-token' })
    const store = useContactsStore()
    const add = vi.spyOn(store, 'add')

    await dialog.submit()

    expect(add).not.toHaveBeenCalled()
    expect(dialog.feedback.value).toEqual({
      kind: 'error',
      title: 'Usuario obrigatorio',
      message: 'Informe o @usuario que deseja adicionar.',
    })
  })

  it('prevents duplicate submissions while a request is pending', async () => {
    const pending = deferred<Contact>()
    const dialog = useAddContactDialog({ token: 'jwt-token' })
    const store = useContactsStore()
    const add = vi.spyOn(store, 'add').mockReturnValue(pending.promise)
    dialog.username.value = '@ana'

    const firstSubmission = dialog.submit()
    await dialog.submit()

    expect(dialog.isSubmitting.value).toBe(true)
    expect(add).toHaveBeenCalledOnce()

    pending.resolve(contact())
    await firstSubmission

    expect(dialog.isSubmitting.value).toBe(false)
  })

  it('clears the username and reports the added contact after success', async () => {
    const dialog = useAddContactDialog({ token: () => 'jwt-token' })
    const store = useContactsStore()
    vi.spyOn(store, 'add').mockResolvedValue(contact())
    dialog.username.value = '@ana'

    await dialog.submit()

    expect(store.add).toHaveBeenCalledWith('@ana', 'jwt-token')
    expect(dialog.username.value).toBe('')
    expect(dialog.feedback.value).toEqual({
      kind: 'success',
      message: 'Ana Beatriz (@ana) entrou na sua lista.',
    })
  })

  it.each([
    ['user_not_found', 'Usuario nao encontrado'],
    ['contact_already_exists', 'Contato ja adicionado'],
    ['self_contact', 'Este e voce'],
  ])('maps %s API errors to specific feedback', async (code, title) => {
    const dialog = useAddContactDialog({ token: 'jwt-token' })
    const store = useContactsStore()
    vi.spyOn(store, 'add').mockRejectedValue(
      new ApiError({ code, detail: 'Detalhe localizado' }, 400),
    )
    dialog.username.value = '@ana'

    await dialog.submit()

    expect(dialog.feedback.value).toEqual({
      kind: 'error',
      title,
      message: 'Detalhe localizado',
    })
    expect(dialog.isSubmitting.value).toBe(false)
  })

  it('uses safe fallback feedback for unknown failures', async () => {
    const dialog = useAddContactDialog({ token: 'jwt-token' })
    const store = useContactsStore()
    vi.spyOn(store, 'add').mockRejectedValue('unexpected failure')
    dialog.username.value = '@ana'

    await dialog.submit()

    expect(dialog.feedback.value).toEqual({
      kind: 'error',
      title: 'Nao foi possivel adicionar',
      message: 'Tente novamente em instantes.',
    })
  })

  it('does not submit without an authenticated token', async () => {
    const dialog = useAddContactDialog({ token: null })
    const store = useContactsStore()
    const add = vi.spyOn(store, 'add')
    dialog.username.value = '@ana'

    await dialog.submit()

    expect(add).not.toHaveBeenCalled()
    expect(dialog.feedback.value).toEqual({ kind: 'idle' })
  })
})

function contact(): Contact {
  return {
    id: 'contact-1',
    user: {
      id: 'user-ana',
      username: 'ana',
      name: 'Ana Beatriz',
      lastSeenAt: null,
      online: false,
    },
  }
}
