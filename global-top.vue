<script setup lang="ts">
/**
 * Booth autoplay: 30 seconds a slide, and the last slide wraps to the first,
 * so the built deck loops forever on the booth screen.
 *
 * On by default in the built site, off in `npm run dev` so the deck stays an
 * authoring tool. `?autoplay` turns it on in dev, `?autoplay=8` changes the
 * seconds per slide, and `?autoplay=off` pauses it anywhere. A slide can set
 * `autoplay: 45` in its frontmatter to override its own duration.
 */
import { onMounted, onUnmounted, watch } from 'vue'
import { useNav } from '@slidev/client'

const DEFAULT_SECONDS = 30

const nav = useNav()
const query = new URLSearchParams(window.location.search)
const param = query.get('autoplay')
const enabled = param !== 'off' && (import.meta.env.PROD || query.has('autoplay'))
const deckSeconds = Number(param) || DEFAULT_SECONDS

let timer: ReturnType<typeof setTimeout> | undefined

function secondsFor(): number {
  const frontmatter = nav.currentSlideRoute.value?.meta?.slide?.frontmatter ?? {}
  return typeof frontmatter.autoplay === 'number' ? frontmatter.autoplay : deckSeconds
}

function arm() {
  clearTimeout(timer)
  if (!enabled || nav.isPrintMode.value || nav.isPresenter.value)
    return
  timer = setTimeout(async () => {
    if (nav.hasNext.value)
      await nav.next()
    else
      await nav.go(1)
  }, secondsFor() * 1000)
}

onMounted(arm)
watch([nav.currentPage, () => nav.clicks.value], arm)
onUnmounted(() => clearTimeout(timer))
</script>

<template>
  <div v-if="enabled" class="autoplay-timer" aria-hidden="true" />
</template>

<style scoped>
/* Invisible; the layer only exists to host the timer. */
.autoplay-timer { display: none; }
</style>
