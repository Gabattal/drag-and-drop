import { makePlugin } from "@luna-park/plugin";

import { draggable } from "@/components/draggable.ts";
import { dropZone } from "@/components/dropZone.ts";

import icon from "./logo.svg";

export default makePlugin({
    description: "Drag and drop primitives for Luna Park",
    editor: {
        components: [
            draggable,
            dropZone
        ]
    },
    icon,
    id: "drag-and-drop",
    name: "Drag and Drop"
});
