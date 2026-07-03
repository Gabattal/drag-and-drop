import { createApp, h, ref } from "vue";

import LDraggable from "../../src/components/LDraggable.vue";
import LDropZone from "../../src/components/LDropZone.vue";

import type { Component } from "vue";

import "./style.css";

const events = ref<Array<unknown>>([]);

function draggable(id: string, label: string) {
    return h(LDraggable as Component, {
        data: { label },
        group: "cards",
        id
    }, () => h("button", {
        class: "card",
        "data-testid": id,
        type: "button"
    }, label));
}

function zone(id: string, children: Array<ReturnType<typeof h>>, moveOnDrop = true) {
    return h(LDropZone as Component, {
        direction: "vertical",
        group: "cards",
        id,
        moveOnDrop,
        onDrop: (event: unknown) => {
            events.value.push(JSON.parse(JSON.stringify(event)));
        }
    }, () => children);
}

const App = {
    setup() {
        return () => h("main", [
            h("section", [
                h("h2", "Source"),
                zone("source", [
                    draggable("a", "Alpha"),
                    draggable("b", "Beta")
                ])
            ]),
            h("section", [
                h("h2", "Target"),
                zone("target", [
                    draggable("c", "Gamma")
                ])
            ]),
            h("section", [
                h("h2", "Controlled Target"),
                zone("controlled", [], false)
            ]),
            h("pre", { id: "events" }, JSON.stringify(events.value, null, 2))
        ]);
    }
};

createApp(App).mount("#app");

declare global {
    interface Window {
        dndHarness: {
            events: typeof events;
            order: (zoneId: string) => Array<string>;
        };
    }
}

window.dndHarness = {
    events,
    order(zoneId: string) {
        const zoneElement = document.querySelector(`[data-dnd-dropzone-id="${ zoneId }"]`);
        if (!zoneElement) return [];
        return Array.from(zoneElement.querySelectorAll<HTMLElement>("[data-dnd-draggable-id]"))
            .map((element) => element.dataset.dndDraggableId ?? "");
    }
};
