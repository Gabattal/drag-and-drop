<template>
    <div
        class="draggable"
        :class="{ 'is-source': isDragging, 'is-disabled': disabled }"
        :data-dnd-draggable-id="effectiveId()"
        :data-dnd-group="group"
        :draggable="!disabled"
        @dragstart="onDragStart"
        @dragend="onDragEnd"
    >
        <slot />
    </div>
</template>

<script setup lang="ts">
import { ref } from "vue";

import { dndState } from "@/components/dndState.ts";

const props = withDefaults(defineProps<{
    data?: unknown;
    disabled?: boolean;
    group?: string;
    id?: string;
}>(), {
    data: undefined,
    disabled: false,
    group: "",
    id: ""
});

const emit = defineEmits<{
    dragEnd: [payload: { data: unknown; group: string; id: string }];
    dragStart: [payload: { data: unknown; group: string; id: string }];
}>();

const isDragging = ref(false);
const autoId = `draggable-${ Math.random().toString(36).slice(2, 10) }`;
const effectiveId = () => props.id || autoId;

let ghost: HTMLElement | null = null;
let source: HTMLElement | null = null;
let ghostWidth = 0;
let ghostHeight = 0;
let offsetX = 0;
let offsetY = 0;
let lastX = 0;
let lastTime = 0;
let velocityX = 0;

const TILT_MULTIPLIER = 3;
const TILT_MAX = 2;
const VELOCITY_SMOOTH = 0.92;
const DROP_ANIM_MS = 240;
const DROP_EASING = "cubic-bezier(0.22, 1, 0.36, 1)";

function sourceLocation(element: HTMLElement): { sourceIndex: number; sourceZoneId: string } {
    const zone = element.closest<HTMLElement>("[data-dnd-dropzone-id]");
    if (!zone) return { sourceIndex: -1, sourceZoneId: "" };

    const children = Array.from(zone.children).filter((child): child is HTMLElement => {
        return child instanceof HTMLElement && child.hasAttribute("data-dnd-draggable-id");
    });

    return {
        sourceIndex: children.indexOf(element),
        sourceZoneId: zone.dataset.dndDropzoneId ?? ""
    };
}

function onDragStart(e: DragEvent) {
    if (props.disabled) {
        e.preventDefault();
        return;
    }

    source = e.currentTarget as HTMLElement;

    const rect = source.getBoundingClientRect();
    ghostWidth = rect.width;
    ghostHeight = rect.height;
    offsetX = e.clientX - rect.left;
    offsetY = e.clientY - rect.top;
    const location = sourceLocation(source);

    dndState.start({
        data: props.data,
        element: source,
        group: props.group,
        height: ghostHeight,
        id: effectiveId(),
        sourceIndex: location.sourceIndex,
        sourceRect: rect,
        sourceZoneId: location.sourceZoneId,
        width: ghostWidth
    });

    if (e.dataTransfer) {
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", "");
        // Hide the browser default drag image with a 1x1 transparent canvas.
        const empty = document.createElement("canvas");
        empty.width = 1;
        empty.height = 1;
        e.dataTransfer.setDragImage(empty, 0, 0);
    }

    ghost = source.cloneNode(true) as HTMLElement;
    ghost.classList.add("draggable-ghost");
    ghost.style.width = `${ ghostWidth }px`;
    ghost.style.height = `${ ghostHeight }px`;
    ghost.style.translate = `${ e.clientX - offsetX }px ${ e.clientY - offsetY }px`;
    document.body.appendChild(ghost);

    lastX = e.clientX;
    lastTime = performance.now();
    velocityX = 0;

    isDragging.value = true;
    document.addEventListener("dragover", onDocumentDragOver);
    emit("dragStart", { data: props.data, group: props.group, id: effectiveId() });
}

function onDocumentDragOver(e: DragEvent) {
    if (!ghost) return;
    if (e.clientX === 0 && e.clientY === 0) return;

    const now = performance.now();
    const dt = Math.max(now - lastTime, 1);
    const dx = e.clientX - lastX;

    velocityX = velocityX * VELOCITY_SMOOTH + (dx / dt) * (1 - VELOCITY_SMOOTH);
    const tilt = Math.max(-TILT_MAX, Math.min(TILT_MAX, velocityX * TILT_MULTIPLIER));

    ghost.style.translate = `${ e.clientX - offsetX }px ${ e.clientY - offsetY }px`;
    ghost.style.rotate = `${ tilt }deg`;

    lastX = e.clientX;
    lastTime = now;
}

function onDragEnd() {
    document.removeEventListener("dragover", onDocumentDragOver);

    const g = ghost;
    const cur = dndState.get();
    const placeholder = cur?.placeholder ?? null;
    const targetRect = cur?.dropRect ?? cur?.sourceRect ?? null;

    ghost = null;
    source = null;
    dndState.end();
    emit("dragEnd", { data: props.data, group: props.group, id: effectiveId() });

    placeholder?.remove();

    if (!g || !targetRect) {
        g?.remove();
        isDragging.value = false;
        return;
    }

    g.style.transition = `translate ${ DROP_ANIM_MS }ms ${ DROP_EASING }, rotate ${ DROP_ANIM_MS }ms ${ DROP_EASING }`;
    g.style.translate = `${ targetRect.left }px ${ targetRect.top }px`;
    g.style.rotate = "0deg";

    let done = false;
    const finish = () => {
        if (done) return;
        done = true;
        g.remove();
        isDragging.value = false;
    };
    g.addEventListener("transitionend", finish, { once: true });
    setTimeout(finish, DROP_ANIM_MS + 50);
}
</script>

<style scoped>
.draggable {
    cursor: grab;
}

.draggable.is-source {
    /* Collapse out of layout; the placeholder takes over visually. */
    display: none;
}

.draggable.is-disabled {
    cursor: not-allowed;
    opacity: 0.6;
}

.draggable-ghost {
    filter: drop-shadow(0 4px 10px rgba(0, 0, 0, 0.12));
    left: 0;
    pointer-events: none;
    position: fixed;
    top: 0;
    transition: rotate 120ms ease-out;
    z-index: 9999;
}
</style>

<style>
.dnd-placeholder {
    background-color: color-mix(in srgb, var(--highlight-color, #3b82f6) 8%, transparent);
    border: 2px dashed var(--highlight-color, #3b82f6);
    border-radius: 6px;
    box-sizing: border-box;
    pointer-events: none;
    transition: opacity 140ms ease-out;
}
</style>
