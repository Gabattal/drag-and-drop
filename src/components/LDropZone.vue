<template>
    <div
        ref="root"
        class="dropzone"
        :class="{ 'is-over': isOver, 'is-disabled': disabled }"
        :data-dnd-dropzone-id="effectiveZoneId()"
        :data-dnd-group="group"
        :style="{ '--highlight-color': highlightColor }"
    >
        <slot />
    </div>
</template>

<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";

import { dndState } from "@/components/dndState.ts";

type TDropLocation = {
    afterId: string;
    beforeId: string;
    index: number;
    zoneId: string;
};

type TDropPayload = TDropLocation & {
    data: unknown;
    group: string;
    id: string;
    sourceIndex: number;
    sourceZoneId: string;
};

type TDragPoint = {
    clientX: number;
    clientY: number;
};

type TPointerDragEvent = CustomEvent<TDragPoint>;

const props = withDefaults(defineProps<{
    direction?: "horizontal" | "vertical";
    disabled?: boolean;
    group?: string;
    highlightColor?: string;
    id?: string;
    moveOnDrop?: boolean;
}>(), {
    direction: "vertical",
    disabled: false,
    group: "",
    highlightColor: "#3b82f6",
    id: "",
    moveOnDrop: true
});

const emit = defineEmits<{
    dragEnter: [payload: { group: string; zoneId: string }];
    dragLeave: [payload: { group: string; zoneId: string }];
    drop: [payload: TDropPayload];
}>();

const root = ref<HTMLElement | null>(null);
const isOver = ref(false);
const pendingLocation = ref<TDropLocation | null>(null);
const autoId = `dropzone-${ Math.random().toString(36).slice(2, 10) }`;
const effectiveZoneId = () => props.id || autoId;
let placeholderFrame = 0;
let pendingPoint: TDragPoint | null = null;
let cleanupTimer = 0;
let measuredElement: HTMLElement | null = null;
let measuredRoot: HTMLElement | null = null;
let measuredWidth = -1;

function accepts(): boolean {
    if (props.disabled) return false;
    const cur = dndState.get();
    if (!cur) return false;
    return cur.group === props.group;
}

function visibleChildren(): Array<HTMLElement> {
    if (!root.value) return [];
    const cur = dndState.get();
    const placeholder = cur?.placeholder;
    return Array.from(root.value.children).filter((child): child is HTMLElement => {
        if (!(child instanceof HTMLElement)) return false;
        if (child === placeholder) return false;
        if (child === cur?.element) return false;
        return true;
    });
}

function childId(child: HTMLElement | null): string {
    return child?.dataset.dndDraggableId ?? "";
}

function computeInsertTarget(point: TDragPoint): HTMLElement | null {
    const cursor = props.direction === "vertical" ? point.clientY : point.clientX;
    for (const child of visibleChildren()) {
        const rect = child.getBoundingClientRect();
        const mid = props.direction === "vertical"
            ? rect.top + rect.height / 2
            : rect.left + rect.width / 2;
        if (cursor < mid) return child;
    }
    return null;
}

function computeLocation(target: HTMLElement | null): TDropLocation {
    const children = visibleChildren();
    const index = target ? children.indexOf(target) : children.length;
    const normalizedIndex = index < 0 ? children.length : index;
    const before = children[normalizedIndex] ?? null;
    const after = normalizedIndex > 0 ? children[normalizedIndex - 1] : null;

    return {
        afterId: childId(after),
        beforeId: childId(before),
        index: normalizedIndex,
        zoneId: effectiveZoneId()
    };
}

function ensurePlaceholder(): HTMLElement {
    const cur = dndState.get();
    if (cur?.placeholder) return cur.placeholder;
    const ph = document.createElement("div");
    measuredElement = null;
    measuredRoot = null;
    measuredWidth = -1;
    ph.classList.add("dnd-placeholder");
    ph.style.backgroundColor = `color-mix(in srgb, ${ props.highlightColor } 8%, transparent)`;
    ph.style.alignSelf = props.direction === "vertical" ? "stretch" : "auto";
    ph.style.border = `2px dashed ${ props.highlightColor }`;
    ph.style.borderRadius = "6px";
    ph.style.boxSizing = "border-box";
    ph.style.display = "block";
    ph.style.flexShrink = "0";
    ph.style.height = props.direction === "vertical" ? `${ cur?.height ?? 0 }px` : "auto";
    ph.style.pointerEvents = "none";
    ph.style.width = props.direction === "vertical" ? "auto" : `${ cur?.width ?? 0 }px`;
    dndState.setPlaceholder(ph);
    return ph;
}

function cssPixels(value: string): number {
    const parsed = Number.parseFloat(value);
    return Number.isNaN(parsed) ? 0 : parsed;
}

function updatePlaceholderSize(placeholder: HTMLElement) {
    const cur = dndState.get();
    if (!cur || !root.value) return;

    if (props.direction === "horizontal") {
        placeholder.style.width = `${ cur.width }px`;
        placeholder.style.height = "auto";
        return;
    }

    const placeholderWidth = placeholder.getBoundingClientRect().width;
    if (
        measuredElement === cur.element
        && measuredRoot === root.value
        && Math.abs(placeholderWidth - measuredWidth) < 0.5
    ) {
        return;
    }

    const measuringElement = cur.element.cloneNode(true) as HTMLElement;
    measuringElement.removeAttribute("data-dnd-draggable-id");
    measuringElement.classList.remove("is-source");
    measuringElement.style.alignSelf = "auto";
    measuringElement.style.boxSizing = "border-box";
    measuringElement.style.display = "block";
    measuringElement.style.opacity = "0";
    measuringElement.style.pointerEvents = "none";
    measuringElement.style.position = "static";
    measuringElement.style.visibility = "hidden";
    measuringElement.style.width = `${ placeholderWidth || root.value.getBoundingClientRect().width }px`;

    placeholder.replaceWith(measuringElement);
    const measuredHeight = measuringElement.getBoundingClientRect().height;
    const measuredStyle = window.getComputedStyle(measuringElement);
    const measuredMargin = cssPixels(measuredStyle.marginTop) + cssPixels(measuredStyle.marginBottom);
    measuringElement.replaceWith(placeholder);

    measuredElement = cur.element;
    measuredRoot = root.value;
    measuredWidth = placeholderWidth;
    placeholder.style.height = `${ (measuredHeight || cur.height) + measuredMargin }px`;
    placeholder.style.width = "auto";
}

function positionPlaceholder(target: HTMLElement | null): TDropLocation | null {
    if (!root.value) return null;
    const placeholder = ensurePlaceholder();
    const currentParent = placeholder.parentNode;
    const currentNext = placeholder.nextSibling;
    const location = computeLocation(target);

    if (!(currentParent === root.value && currentNext === target)) {
        if (target) root.value.insertBefore(placeholder, target);
        else root.value.appendChild(placeholder);
    }

    updatePlaceholderSize(placeholder);
    pendingLocation.value = location;
    return location;
}

function ownPlaceholder(): HTMLElement | null {
    if (!root.value) return null;

    return Array.from(root.value.children).find((child): child is HTMLElement => {
        return child instanceof HTMLElement && child.classList.contains("dnd-placeholder");
    }) ?? null;
}

function removeOwnPlaceholder(force = false) {
    cancelPlaceholderFrame();
    const cur = dndState.get();
    const placeholder = cur?.placeholder ?? ownPlaceholder();
    if (!placeholder || placeholder.parentNode !== root.value) return;
    if (!force && placeholder.dataset.dndMoveOnDrop === "true") return;

    placeholder.remove();
    if (cur?.placeholder === placeholder) dndState.setPlaceholder(null);
    measuredElement = null;
    measuredRoot = null;
    measuredWidth = -1;
    pendingLocation.value = null;
}

function scheduleForcedCleanup() {
    if (cleanupTimer) window.clearTimeout(cleanupTimer);
    cleanupTimer = window.setTimeout(() => {
        cleanupTimer = 0;
        removeOwnPlaceholder(true);
    }, 600);
}

function enter() {
    if (isOver.value) return;
    isOver.value = true;
    emit("dragEnter", { group: props.group, zoneId: effectiveZoneId() });
}

function leave() {
    if (!isOver.value) return;
    isOver.value = false;
    emit("dragLeave", { group: props.group, zoneId: effectiveZoneId() });
}

function cancelPlaceholderFrame() {
    if (!placeholderFrame) return;
    cancelAnimationFrame(placeholderFrame);
    placeholderFrame = 0;
    pendingPoint = null;
}

function flushPlaceholderFrame() {
    placeholderFrame = 0;
    if (!pendingPoint) return;

    positionPlaceholder(computeInsertTarget(pendingPoint));
    pendingPoint = null;
}

function schedulePlaceholder(point: TDragPoint) {
    pendingPoint = {
        clientX: point.clientX,
        clientY: point.clientY
    };
    if (placeholderFrame) return;
    placeholderFrame = requestAnimationFrame(flushPlaceholderFrame);
}

function eventPoint(event: Event): TDragPoint {
    return (event as TPointerDragEvent).detail;
}

function onPointerMove(event: Event) {
    if (!accepts()) return;
    schedulePlaceholder(eventPoint(event));
    enter();
}

function onPointerLeave() {
    removeOwnPlaceholder();
    leave();
}

function onPointerDrop(event: Event) {
    if (!accepts()) return;
    const point = eventPoint(event);
    cancelPlaceholderFrame();
    positionPlaceholder(computeInsertTarget(point));
    const cur = dndState.get();
    if (!cur || !root.value) return;

    const placeholder = cur.placeholder;
    if (placeholder && placeholder.parentNode === root.value) {
        // The source is hidden, so the placeholder is the stable animation target.
        dndState.setDropRect(placeholder.getBoundingClientRect());
        if (props.moveOnDrop) placeholder.dataset.dndMoveOnDrop = "true";
    } else if (props.moveOnDrop && cur.element.parentNode !== root.value) {
        root.value.appendChild(cur.element);
    }

    const location = pendingLocation.value ?? computeLocation(null);
    pendingLocation.value = null;
    leave();
    scheduleForcedCleanup();

    emit("drop", {
        data: cur.data,
        group: cur.group,
        id: cur.id,
        sourceIndex: cur.sourceIndex,
        sourceZoneId: cur.sourceZoneId,
        ...location
    });
}

onMounted(() => {
    root.value?.addEventListener("dndpointermove", onPointerMove);
    root.value?.addEventListener("dndpointerleave", onPointerLeave);
    root.value?.addEventListener("dndpointerdrop", onPointerDrop);
});

onUnmounted(() => {
    if (cleanupTimer) window.clearTimeout(cleanupTimer);
    cancelPlaceholderFrame();
    root.value?.removeEventListener("dndpointermove", onPointerMove);
    root.value?.removeEventListener("dndpointerleave", onPointerLeave);
    root.value?.removeEventListener("dndpointerdrop", onPointerDrop);
});
</script>

<style scoped>
.dropzone {
    --highlight-color: #3b82f6;
    border: 2px dashed transparent;
    min-height: 40px;
    position: relative;
    transition: border-color 0.15s, background-color 0.15s;
}

.dropzone.is-over {
    background-color: color-mix(in srgb, var(--highlight-color) 6%, transparent);
    border-color: color-mix(in srgb, var(--highlight-color) 60%, transparent);
}

.dropzone.is-disabled {
    opacity: 0.5;
}
</style>
