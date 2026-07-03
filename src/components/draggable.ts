import { LogicType, type TComponent } from "@luna-park/plugin";

import LDraggable from "@/components/LDraggable.vue";

export const draggable: TComponent = {
    component: LDraggable,
    emits: {
        dragEnd: LogicType.object({
            data: LogicType.unknown(),
            group: LogicType.string(),
            id: LogicType.string()
        }, { name: "DragEvent" }),
        dragStart: LogicType.object({
            data: LogicType.unknown(),
            group: LogicType.string(),
            id: LogicType.string()
        }, { name: "DragEvent" })
    },
    name: "DragAndDrop/Draggable",
    properties: {
        data: LogicType.unknown(),
        disabled: LogicType.boolean({ default: false }),
        group: LogicType.string({ default: "" }),
        id: LogicType.string({ default: "" })
    },
    slots: {
        default: LogicType.void()
    }
};
