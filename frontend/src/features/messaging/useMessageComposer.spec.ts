import { describe, expect, it, vi } from 'vitest'

import { useMessageComposer } from './useMessageComposer'

describe('useMessageComposer', () => {
  it('ignores whitespace-only drafts', () => {
    const send = vi.fn()
    const composer = useMessageComposer({ send })
    composer.draft.value = '   '

    composer.submit()

    expect(send).not.toHaveBeenCalled()
    expect(composer.draft.value).toBe('   ')
  })

  it('keeps the draft when the transport rejects the send', () => {
    const send = vi.fn().mockReturnValue(false)
    const composer = useMessageComposer({ send })
    composer.draft.value = '  Mensagem pendente  '

    composer.submit()

    expect(send).toHaveBeenCalledWith('Mensagem pendente')
    expect(composer.draft.value).toBe('  Mensagem pendente  ')
  })

  it('clears the draft only after a successful send', () => {
    const send = vi.fn().mockReturnValue(true)
    const composer = useMessageComposer({ send })
    composer.draft.value = '  Mensagem enviada  '

    composer.submit()

    expect(send).toHaveBeenCalledWith('Mensagem enviada')
    expect(composer.draft.value).toBe('')
  })
})
