<template>
    <div
        ref="root"
        class="dropzone"
        :class="{ 'is-over': isOver, 'is-disabled': disabled }"
        :data-dnd-dropzone-id="effectiveZoneId()"
        :data-dnd-group="group"
        :style="{ '--highlight-color': highlightColor }"
        @dragenter="onDragEnter"
        @dragover="onDragOver"
        @dragleave="onDragLeave"
        @drop="onDrop"
    >
        <slot />
    </div>
</template>

<script setup lang="ts">
import { ref } from "vue";

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

function accepts(): boolean {
    if (props.disabled) return false;
    const cur = dndState.get();
    if (!cur) return false;
    return cur.group === props.group;
}

function setDropEffect(e: DragEvent) {
    if (e.dataTransfer) e.dataTransfer.dropEffect = "move";
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

function computeInsertTarget(e: DragEvent): HTMLElement | null {
    const cursor = props.direction === "vertical" ? e.clientY : e.clientX;
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
    ph.classList.add("dnd-placeholder");
    ph.style.width = `${ cur?.width ?? 0 }px`;
    ph.style.height = `${ cur?.height ?? 0 }px`;
    dndState.setPlaceholder(ph);
    return ph;
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

    pendingLocation.value = location;
    return location;
}

function removeOwnPlaceholder() {
    const cur = dndState.get();
    const placeholder = cur?.placeholder;
    if (!placeholder || placeholder.parentNode !== root.value) return;
    placeholder.remove();
    dndState.setPlaceholder(null);
    pendingLocation.value = null;
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

function onDragEnter(e: DragEvent) {
    if (!accepts()) return;
    e.preventDefault();
    setDropEffect(e);
    enter();
}

function onDragOver(e: DragEvent) {
    if (!accepts()) return;
    e.preventDefault();
    setDropEffect(e);
    positionPlaceholder(computeInsertTarget(e));
    enter();
}

function onDragLeave(e: DragEvent) {
    const related = e.relatedTarget as Node | null;
    if (related && (e.currentTarget as Node).contains(related)) return;
    removeOwnPlaceholder();
    leave();
}

function onDrop(e: DragEvent) {
    if (!accepts()) return;
    e.preventDefault();
    const cur = dndState.get();
    if (!cur || !root.value) return;

    const placeholder = cur.placeholder;
    if (placeholder && placeholder.parentNode === root.value) {
        // The source is hidden, so the placeholder is the stable animation target.
        dndState.setDropRect(placeholder.getBoundingClientRect());
        if (props.moveOnDrop) root.value.insertBefore(cur.element, placeholder);
        placeholder.remove();
        dndState.setPlaceholder(null);
    } else if (props.moveOnDrop && cur.element.parentNode !== root.value) {
        root.value.appendChild(cur.element);
    }

    const location = pendingLocation.value ?? computeLocation(null);
    pendingLocation.value = null;
    leave();

    emit("drop", {
        data: cur.data,
        group: cur.group,
        id: cur.id,
        sourceIndex: cur.sourceIndex,
        sourceZoneId: cur.sourceZoneId,
        ...location
    });
}
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
