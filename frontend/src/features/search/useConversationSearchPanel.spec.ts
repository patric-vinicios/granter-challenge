import { nextTick, shallowRef } from 'vue'
import { describe, expect, it } from 'vitest'

import { withSetup } from '@/test/composable'

import { useConversationSearchPanel } from './useConversationSearchPanel'

describe('useConversationSearchPanel', () => {
  it('closes and clears search when the selected conversation changes', async () => {
    const conversationId = shallowRef<string | null>('conversation-1')
    const { result, unmount } = withSetup(() =>
      useConversationSearchPanel({
        token: 'jwt-token',
        conversationId,
      }),
    )

    result.open()
    result.term.value = 'cronograma'

    expect(result.isOpen.value).toBe(true)
    expect(result.term.value).toBe('cronograma')

    conversationId.value = 'conversation-2'
    await nextTick()

    expect(result.isOpen.value).toBe(false)
    expect(result.term.value).toBe('')

    unmount()
  })
})
