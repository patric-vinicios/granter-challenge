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
        isHighlighted ? 'ring-2 ring-yellow-300 ring-offset-2' : '',
        side === 'out'
          ? 'border-black bg-black text-white'
          : 'border-[#e8e8e8] bg-white text-[#171717]',
      ]"
    >
      <strong v-if="author" class="mb-1 block text-[13px] text-[#171717]">{{ author }}</strong>
      <div>
        <template v-if="textSegments.length > 1">
          <template v-for="(segment, index) in textSegments" :key="`${index}-${segment.text}`">
            <mark v-if="segment.highlight" class="rounded bg-yellow-200 px-0.5 text-black">
              {{ segment.text }}
            </mark>
            <span v-else>{{ segment.text }}</span>
          </template>
        </template>
        <template v-else>{{ text }}</template>
      </div>
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
import { computed } from 'vue'

interface HighlightRange {
  start: number
  length: number
}

const props = withDefaults(
  defineProps<{
    side: 'in' | 'out'
    text: string
    time: string
    wide?: boolean
    author?: string
    isHighlighted?: boolean
    highlightRanges?: HighlightRange[]
  }>(),
  {
    wide: false,
    author: undefined,
    isHighlighted: false,
    highlightRanges: () => [],
  },
)

const textSegments = computed(() => splitText(props.text, props.highlightRanges))

function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase()
}

function splitText(text: string, ranges: HighlightRange[]) {
  const segments: Array<{ text: string; highlight: boolean }> = []
  let cursor = 0

  for (const range of normalizedRanges(text, ranges)) {
    if (range.start > cursor) {
      segments.push({ text: text.slice(cursor, range.start), highlight: false })
    }

    segments.push({ text: text.slice(range.start, range.start + range.length), highlight: true })
    cursor = range.start + range.length
  }

  if (cursor < text.length || segments.length === 0) {
    segments.push({ text: text.slice(cursor), highlight: false })
  }

  return segments
}

function normalizedRanges(text: string, ranges: HighlightRange[]): HighlightRange[] {
  return ranges
    .filter((range) => range.start >= 0 && range.length > 0 && range.start < text.length)
    .map((range) => ({ start: range.start, length: Math.min(range.length, text.length - range.start) }))
    .sort((left, right) => left.start - right.start)
    .filter((range, index, sorted) => index === 0 || range.start >= sorted[index - 1].start + sorted[index - 1].length)
}
</script>
