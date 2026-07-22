<template>
  <div
    class="flex items-end gap-2"
    :class="side === 'out' ? 'justify-end' : 'justify-start'"
  >
    <span
      v-if="side === 'in' && author"
      class="grid h-8 w-8 shrink-0 place-items-center rounded-full border border-[#e8e8e8] bg-[#f4f4f5] text-[11px] font-bold text-[#444444]"
    >
      {{ initials(author) }}
    </span>
    <div
      class="rounded-lg border px-3 py-2 text-[14px] leading-5 shadow-none"
      :class="[
        wide ? 'max-w-[354px]' : 'max-w-[310px]',
        side === 'out'
          ? 'border-black bg-black text-white'
          : 'border-[#e8e8e8] bg-white text-[#171717]',
      ]"
    >
      <strong v-if="author" class="mb-1 block text-[13px] text-[#171717]">{{ author }}</strong>
      <div>{{ text }}</div>
      <div
        class="mt-1 text-right text-[12px]"
        :class="side === 'out' ? 'text-[#8d8d8d]' : 'text-[#a3a3a3]'"
      >
        {{ time }}
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    side: 'in' | 'out'
    text: string
    time: string
    wide?: boolean
    author?: string
  }>(),
  {
    wide: false,
    author: undefined,
  },
)

function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase()
}
</script>
