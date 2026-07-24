import { shallowRef } from 'vue'

interface UseMessageComposerOptions {
  send: (body: string) => boolean
}

export function useMessageComposer({ send }: UseMessageComposerOptions) {
  const draft = shallowRef('')

  function submit(): void {
    const body = draft.value.trim()

    if (!body) {
      return
    }

    if (!send(body)) {
      return
    }

    draft.value = ''
  }

  return {
    draft,
    submit,
  }
}
