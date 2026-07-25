import {
  getCurrentScope,
  onScopeDispose,
  shallowRef,
  toValue,
  watch,
  type MaybeRefOrGetter,
  type ShallowRef,
} from 'vue'

interface UseDebouncedValueOptions<T> {
  delayMs?: number
  immediateWhen?: (value: T) => boolean
}

export function useDebouncedValue<T>(
  source: MaybeRefOrGetter<T>,
  { delayMs = 1000, immediateWhen }: UseDebouncedValueOptions<T> = {},
): ShallowRef<T> {
  const debounced = shallowRef(toValue(source)) as ShallowRef<T>
  let timer: ReturnType<typeof setTimeout> | undefined

  function clearTimer(): void {
    if (timer === undefined) {
      return
    }

    clearTimeout(timer)
    timer = undefined
  }

  watch(
    () => toValue(source),
    (value) => {
      clearTimer()

      if (Object.is(value, debounced.value)) {
        return
      }

      if (delayMs <= 0 || immediateWhen?.(value)) {
        debounced.value = value
        return
      }

      timer = setTimeout(() => {
        debounced.value = value
        timer = undefined
      }, delayMs)
    },
    { flush: 'sync' },
  )

  if (getCurrentScope()) {
    onScopeDispose(clearTimer)
  }

  return debounced
}
