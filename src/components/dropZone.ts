import { LogicType, type TComponent } from "@luna-park/plugin";

import LDropZone from "@/components/LDropZone.vue";

export const dropZone: TComponent = {
    component: LDropZone,
    emits: {
        dragEnter: LogicType.object({
            group: LogicType.string(),
            zoneId: LogicType.string()
        }, { name: "DropZoneEvent" }),
        dragLeave: LogicType.object({
            group: LogicType.string(),
            zoneId: LogicType.string()
        }, { name: "DropZoneEvent" }),
        drop: LogicType.object({
            afterId: LogicType.string(),
            beforeId: LogicType.string(),
            data: LogicType.unknown(),
            group: LogicType.string(),
            id: LogicType.string(),
            index: LogicType.number(),
            sourceIndex: LogicType.number(),
            sourceZoneId: LogicType.string(),
            zoneId: LogicType.string()
        }, { name: "DropEvent" })
    },
    name: "DragAndDrop/DropZone",
    properties: {
        direction: LogicType.string({ default: "vertical", enum: ["vertical", "horizontal"] }),
        disabled: LogicType.boolean({ default: false }),
        group: LogicType.string({ default: "" }),
        highlightColor: LogicType.string({ default: "#3b82f6" }),
        id: LogicType.string({ default: "" }),
        moveOnDrop: LogicType.boolean({ default: true })
    },
    slots: {
        default: LogicType.void()
    }
};
