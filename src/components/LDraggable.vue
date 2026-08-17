<template>
    <div
        class="draggable"
        :class="{ 'is-source': isDragging, 'is-disabled': disabled }"
        :data-dnd-draggable-id="effectiveId()"
        :data-dnd-group="group"
        :draggable="false"
        @pointerdown="onPointerDown"
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
let activeZone: HTMLElement | null = null;
let ghostWidth = 0;
let ghostHeight = 0;
let offsetX = 0;
let offsetY = 0;
let lastX = 0;
let lastTime = 0;
let moveFrame = 0;
let pendingX = 0;
let pendingY = 0;
let activePointerId = 0;
let velocityX = 0;

const TILT_MULTIPLIER = 3;
const TILT_MAX = 2;
const VELOCITY_SMOOTH = 0.92;
const DROP_ANIM_MS = 240;
const DROP_EASING = "cubic-bezier(0.22, 1, 0.36, 1)";
const PLACEHOLDER_HOLD_MS = 180;
const INHERITED_GHOST_PROPERTIES = [
    "color",
    "font-family",
    "font-size",
    "font-style",
    "font-weight",
    "letter-spacing",
    "line-height",
    "text-align"
];
const VISUAL_GHOST_PROPERTIES = [
    "align-items",
    "background-color",
    "border-radius",
    "color",
    "display",
    "font-family",
    "font-size",
    "font-style",
    "font-weight",
    "height",
    "justify-content",
    "letter-spacing",
    "line-height",
    "max-height",
    "max-width",
    "min-height",
    "min-width",
    "overflow",
    "padding-bottom",
    "padding-left",
    "padding-right",
    "padding-top",
    "text-align",
    "text-decoration-color",
    "text-decoration-line",
    "text-overflow",
    "text-transform",
    "vertical-align",
    "white-space",
    "width"
];

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

function copyInheritedCustomProperties(from: Element, to: Element) {
    if (!(to instanceof HTMLElement || to instanceof SVGElement)) return;

    const computed = window.getComputedStyle(from);
    for (const property of INHERITED_GHOST_PROPERTIES) {
        to.style.setProperty(property, computed.getPropertyValue(property));
    }

    for (let i = 0; i < computed.length; i++) {
        const property = computed.item(i);
        if (property.startsWith("--")) {
            to.style.setProperty(property, computed.getPropertyValue(property));
        }
    }
}

function copyElementState(from: Element, to: Element) {
    if (from instanceof HTMLCanvasElement && to instanceof HTMLCanvasElement) {
        to.getContext("2d")?.drawImage(from, 0, 0);
    }

    if (from instanceof HTMLTextAreaElement && to instanceof HTMLTextAreaElement) {
        to.value = from.value;
    }

    if (from instanceof HTMLInputElement && to instanceof HTMLInputElement) {
        to.checked = from.checked;
        to.value = from.value;
    }

    if (from instanceof HTMLSelectElement && to instanceof HTMLSelectElement) {
        to.value = from.value;
    }
}

function hasExternalClass(element: Element): boolean {
    if (!(element instanceof HTMLElement || element instanceof SVGElement)) return false;

    for (const className of Array.from(element.classList)) {
        if (!className.startsWith("lp_")) return true;
    }

    return false;
}

function copyVisualProperties(from: Element, to: Element) {
    if (!(to instanceof HTMLElement || to instanceof SVGElement)) return;

    const computed = window.getComputedStyle(from);
    for (const property of VISUAL_GHOST_PROPERTIES) {
        to.style.setProperty(property, computed.getPropertyValue(property));
    }
}

function copyRenderedElement(from: Element, to: Element) {
    copyElementState(from, to);

    const fromElements = Array.from(from.querySelectorAll("*"));
    const toElements = Array.from(to.querySelectorAll("*"));

    for (const [index, element] of fromElements.entries()) {
        const clonedElement = toElements[index];
        if (!clonedElement) continue;

        copyElementState(element, clonedElement);
        if (hasExternalClass(element)) copyVisualProperties(element, clonedElement);
    }
}

function ghostTransform(x: number, y: number, tilt = 0): string {
    return `translate3d(${ x - offsetX }px, ${ y - offsetY }px, 0) rotate(${ tilt }deg) scale(1, 1)`;
}

function lockElementSize(element: HTMLElement) {
    element.style.boxSizing = "border-box";
    element.style.flex = "0 0 auto";
    element.style.width = `${ ghostWidth }px`;
    element.style.height = `${ ghostHeight }px`;
}

function removeStaleDragArtifacts() {
    for (const element of Array.from(document.querySelectorAll(".dnd-placeholder, .draggable-ghost"))) {
        element.remove();
    }
}

function zoneAtPoint(x: number, y: number): HTMLElement | null {
    for (const element of document.elementsFromPoint(x, y)) {
        const zone = element.closest<HTMLElement>("[data-dnd-dropzone-id]");
        if (zone?.dataset.dndGroup === props.group) return zone;
    }

    return null;
}

function emitZoneEvent(zone: HTMLElement, type: string, x: number, y: number) {
    zone.dispatchEvent(new CustomEvent(type, {
        detail: { clientX: x, clientY: y },
        bubbles: false
    }));
}

function updateActiveZone(x: number, y: number) {
    const nextZone = zoneAtPoint(x, y);
    if (activeZone && activeZone !== nextZone) {
        emitZoneEvent(activeZone, "dndpointerleave", x, y);
    }

    activeZone = nextZone;
    if (activeZone) emitZoneEvent(activeZone, "dndpointermove", x, y);
}

function onPointerDown(e: PointerEvent) {
    if (props.disabled) {
        e.preventDefault();
        return;
    }
    if (e.button !== 0) return;

    e.preventDefault();
    removeStaleDragArtifacts();
    source = e.currentTarget as HTMLElement;
    activePointerId = e.pointerId;
    source.setPointerCapture(activePointerId);

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

    ghost = source.cloneNode(true) as HTMLElement;
    copyInheritedCustomProperties(source, ghost);
    copyRenderedElement(source, ghost);
    ghost.classList.add("draggable-ghost");
    ghost.style.boxShadow = "0 12px 30px rgba(15, 23, 42, 0.16)";
    ghost.style.boxSizing = "border-box";
    ghost.style.contain = "layout paint";
    ghost.style.left = "0";
    ghost.style.margin = "0";
    ghost.style.pointerEvents = "none";
    ghost.style.position = "fixed";
    ghost.style.top = "0";
    ghost.style.transition = "none";
    ghost.style.willChange = "transform";
    ghost.style.zIndex = "9999";
    ghost.style.width = `${ ghostWidth }px`;
    ghost.style.height = `${ ghostHeight }px`;
    ghost.style.transform = ghostTransform(e.clientX, e.clientY);
    document.body.appendChild(ghost);

    lastX = e.clientX;
    lastTime = performance.now();
    pendingX = e.clientX;
    pendingY = e.clientY;
    velocityX = 0;

    isDragging.value = true;
    document.addEventListener("pointermove", onDocumentPointerMove, { passive: false });
    document.addEventListener("pointerup", onDocumentPointerUp);
    document.addEventListener("pointercancel", onDocumentPointerCancel);
    emit("dragStart", { data: props.data, group: props.group, id: effectiveId() });
    updateActiveZone(e.clientX, e.clientY);
}

function onDocumentPointerMove(e: PointerEvent) {
    if (e.pointerId !== activePointerId) return;
    if (!ghost) return;
    e.preventDefault();

    pendingX = e.clientX;
    pendingY = e.clientY;
    updateActiveZone(e.clientX, e.clientY);
    if (moveFrame) return;

    moveFrame = requestAnimationFrame(moveGhost);
}

function moveGhost() {
    if (!ghost) return;
    moveFrame = 0;

    const now = performance.now();
    const dt = Math.max(now - lastTime, 1);
    const dx = pendingX - lastX;

    velocityX = velocityX * VELOCITY_SMOOTH + (dx / dt) * (1 - VELOCITY_SMOOTH);
    const tilt = Math.max(-TILT_MAX, Math.min(TILT_MAX, velocityX * TILT_MULTIPLIER));

    ghost.style.transform = ghostTransform(pendingX, pendingY, tilt);

    lastX = pendingX;
    lastTime = now;
}

function removePointerListeners() {
    document.removeEventListener("pointermove", onDocumentPointerMove);
    document.removeEventListener("pointerup", onDocumentPointerUp);
    document.removeEventListener("pointercancel", onDocumentPointerCancel);
}

function onDocumentPointerUp(e: PointerEvent) {
    if (e.pointerId !== activePointerId) return;
    e.preventDefault();
    updateActiveZone(e.clientX, e.clientY);
    if (activeZone) emitZoneEvent(activeZone, "dndpointerdrop", e.clientX, e.clientY);
    finishDrag();
}

function onDocumentPointerCancel(e: PointerEvent) {
    if (e.pointerId !== activePointerId) return;
    if (activeZone) emitZoneEvent(activeZone, "dndpointerleave", e.clientX, e.clientY);
    finishDrag();
}

function finishDrag() {
    removePointerListeners();
    if (moveFrame) cancelAnimationFrame(moveFrame);
    moveFrame = 0;
    if (source?.hasPointerCapture(activePointerId)) source.releasePointerCapture(activePointerId);

    const g = ghost;
    const cur = dndState.get();
    const placeholder = cur?.placeholder ?? null;
    const droppedElement = cur?.element ?? null;
    let targetRect = cur?.dropRect ?? cur?.sourceRect ?? null;
    let settledElement: HTMLElement | null = null;
    let previousVisibility = "";
    let previousVisibilityPriority = "";

    if (placeholder?.dataset.dndMoveOnDrop === "true" && droppedElement) {
        previousVisibility = droppedElement.style.getPropertyValue("visibility");
        previousVisibilityPriority = droppedElement.style.getPropertyPriority("visibility");
        droppedElement.style.setProperty("visibility", "hidden", "important");
        lockElementSize(droppedElement);
        droppedElement.classList.remove("is-source");
        placeholder.replaceWith(droppedElement);
        settledElement = droppedElement;
        isDragging.value = false;
    }

    ghost = null;
    source = null;
    activeZone = null;
    activePointerId = 0;
    dndState.end();
    emit("dragEnd", { data: props.data, group: props.group, id: effectiveId() });

    if (!g || !targetRect) {
        g?.remove();
        placeholder?.remove();
        isDragging.value = false;
        if (settledElement) {
            settledElement.style.setProperty("visibility", previousVisibility, previousVisibilityPriority);
        }
        return;
    }

    let done = false;
    let dropFrame = requestAnimationFrame(animateDrop);

    function animateDrop() {
        dropFrame = 0;
        if (settledElement) targetRect = settledElement.getBoundingClientRect();
        if (!targetRect) return;

        g.style.transition = `transform ${ DROP_ANIM_MS }ms ${ DROP_EASING }`;
        g.style.transform = `translate3d(${ targetRect.left }px, ${ targetRect.top }px, 0) rotate(0deg) scale(1, 1)`;
    }

    const finish = () => {
        if (done) return;
        done = true;
        if (dropFrame) cancelAnimationFrame(dropFrame);
        g.remove();
        isDragging.value = false;
        if (settledElement) {
            settledElement.style.setProperty("visibility", previousVisibility, previousVisibilityPriority);
            return;
        }

        if (placeholder) placeholder.style.opacity = "0";
        setTimeout(() => placeholder?.remove(), PLACEHOLDER_HOLD_MS);
    };
    g.addEventListener("transitionend", finish, { once: true });
    setTimeout(finish, DROP_ANIM_MS + 50);
}
</script>

<style scoped>
.draggable {
    cursor: grab;
    touch-action: none;
    user-select: none;
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
    box-shadow: 0 12px 30px rgba(15, 23, 42, 0.16);
    contain: layout paint;
    left: 0;
    pointer-events: none;
    position: fixed;
    top: 0;
    transition: none;
    will-change: transform;
    z-index: 9999;
}
</style>

<style>
.dnd-placeholder {
    align-self: stretch;
    background-color: color-mix(in srgb, var(--highlight-color, #3b82f6) 8%, transparent);
    border: 2px dashed var(--highlight-color, #3b82f6);
    border-radius: 6px;
    box-sizing: border-box;
    display: block;
    flex-shrink: 0;
    pointer-events: none;
    transition: opacity 140ms ease-out;
}
</style>
