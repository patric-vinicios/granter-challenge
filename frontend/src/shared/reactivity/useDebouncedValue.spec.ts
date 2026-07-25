import { shallowRef } from 'vue'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { withSetup } from '@/test/composable'

import { useDebouncedValue } from './useDebouncedValue'

describe('useDebouncedValue', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('updates only after the debounce delay', async () => {
    vi.useFakeTimers()
    const source = shallowRef('')
    const setup = withSetup(() => useDebouncedValue(source, { delayMs: 800 }))

    source.value = 'ana'
    expect(setup.result.value).toBe('')

    await vi.advanceTimersByTimeAsync(799)
    expect(setup.result.value).toBe('')

    await vi.advanceTimersByTimeAsync(1)
    expect(setup.result.value).toBe('ana')

    setup.unmount()
  })

  it('resets immediately when the immediate predicate matches', () => {
    vi.useFakeTimers()
    const source = shallowRef('ana')
    const setup = withSetup(() =>
      useDebouncedValue(source, {
        delayMs: 800,
        immediateWhen: (value) => value.trim() === '',
      }),
    )

    source.value = ''

    expect(setup.result.value).toBe('')
    setup.unmount()
  })
})
