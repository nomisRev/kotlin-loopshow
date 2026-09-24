<script setup lang="ts">
/**
 * Booth autoplay. Off by default so `npm run dev` stays an authoring tool;
 * `?autoplay` (or `?autoplay=8` for eight seconds a slide) turns it on.
 * A slide's `autoplay:` frontmatter overrides its own duration, a Magic Move
 * step defaults to a shorter hold, and the last slide wraps to the first.
 */
import { onMounted, onUnmounted, watch } from 'vue'
import { useNav } from '@slidev/client'

const DEFAULT_SECONDS = 10
const MAGIC_MOVE_SECONDS = 6

const nav = useNav()
const query = new URLSearchParams(window.location.search)
const enabled = query.has('autoplay')
const deckSeconds = Number(query.get('autoplay')) || DEFAULT_SECONDS

let timer: ReturnType<typeof setTimeout> | undefined

function secondsFor(): number {
  const frontmatter = nav.currentSlideRoute.value?.meta?.slide?.frontmatter ?? {}
  if (typeof frontmatter.autoplay === 'number')
    return frontmatter.autoplay
  return frontmatter.magicMove ? Math.min(MAGIC_MOVE_SECONDS, deckSeconds) : deckSeconds
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
  <div v-if="enabled" class="autoplay-badge" aria-hidden="true" />
</template>

<style scoped>
/* Invisible; the layer only exists to host the timer. */
.autoplay-badge { display: none; }
</style>
