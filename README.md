# Luna Park Drag and Drop Plugin

Drag and drop primitives for **Luna Park**. The plugin provides two composable
components, `Draggable` and `DropZone`, that can wrap arbitrary content.

Package name: `@gabattal/drag-and-drop`

## Components

### `DragAndDrop/Draggable`

Wrap content that can be dragged.

| Prop | Type | Default | Description |
|---|---|---|---|
| `id` | `string` | `""` | Stable item id. If omitted, a runtime id is generated. |
| `data` | `unknown` | - | Payload carried by the drag. |
| `group` | `string` | `""` | Only matching drop zones accept the item. |
| `disabled` | `boolean` | `false` | Disables dragging. |

| Emit | Payload | Fires when |
|---|---|---|
| `dragStart` | `{ data, group, id }` | Drag begins. |
| `dragEnd` | `{ data, group, id }` | Drag ends, after drop or cancel. |

### `DragAndDrop/DropZone`

Wrap content that can receive dragged items.

| Prop | Type | Default | Description |
|---|---|---|---|
| `id` | `string` | `""` | Stable zone id. If omitted, a runtime id is generated. |
| `group` | `string` | `""` | Only matching draggables are accepted. |
| `direction` | `"vertical" \| "horizontal"` | `"vertical"` | Layout direction used to compute insertion index. |
| `disabled` | `boolean` | `false` | Refuses all drops. |
| `highlightColor` | `string` | `"#3b82f6"` | Placeholder and hover color. |
| `moveOnDrop` | `boolean` | `true` | Moves the source DOM node to the placeholder on drop. Set to `false` for fully controlled data-driven lists. |

| Emit | Payload | Fires when |
|---|---|---|
| `dragEnter` | `{ group, zoneId }` | A compatible draggable enters the zone. |
| `dragLeave` | `{ group, zoneId }` | A compatible draggable leaves the zone. |
| `drop` | `DropEvent` | A compatible draggable is released over the zone. |

`DropEvent`:

| Field | Type | Description |
|---|---|---|
| `data` | `unknown` | Dragged payload. |
| `id` | `string` | Dragged item id. |
| `group` | `string` | Drag group. |
| `zoneId` | `string` | Target zone id. |
| `index` | `number` | Insertion index in the target zone, computed after removing the dragged source from the list. |
| `beforeId` | `string` | Item id currently after the insertion point, or `""`. |
| `afterId` | `string` | Item id currently before the insertion point, or `""`. |
| `sourceZoneId` | `string` | Original zone id, or `""` when unknown. |
| `sourceIndex` | `number` | Original index, or `-1` when unknown. |

## Behavior

- Native HTML drag events are used: `dragstart` on `Draggable`, `dragenter` /
  `dragover` / `dragleave` / `drop` on `DropZone`.
- `dragover` calls `preventDefault()` only for compatible drags. This is what
  allows the browser to fire `drop`.
- A placeholder is moved inside the target zone while dragging to show the
  insertion point.
- On `drop`, the plugin emits a data event and, by default, also moves the real
  source DOM node to the placeholder so the item does not snap back.
- Update your Luna Park state from the `drop` event when the content is rendered
  from data. The DOM move is an optimistic visual commit; your model should still
  become the source of truth.

## Recommended usage

Render draggable items from data and update that data in the `drop` handler.

```ts
function onDrop(event: DropEvent) {
    moveItem({
        id: event.id,
        fromZoneId: event.sourceZoneId,
        toZoneId: event.zoneId,
        toIndex: event.index
    });
}
```

This keeps the application model as the source of truth. Direct DOM moves can
look correct, but Vue or Luna Park can still revert them on the next render if
the underlying data was not updated.

## Development

- Install dependencies: `pnpm install`
- Build: `pnpm build`
- Watch: `pnpm dev`
- Preview: `pnpm preview`
- Drag and drop regression test: `pnpm test:dnd`

## Publishing

Before publishing, make sure `origin` points to your fork or repository, not to
`git@github.com:lunapark/plugin-boilerplate.git`.

Recommended release check:

```powershell
pnpm test:dnd
pnpm build
pnpm pack --dry-run
```

Publish to npm:

```powershell
npm login
npm publish --access public
```

## Project structure

- `src/index.ts` - plugin entry and component registration.
- `src/components/draggable.ts` + `LDraggable.vue` - draggable definition and Vue implementation.
- `src/components/dropZone.ts` + `LDropZone.vue` - drop zone definition and Vue implementation.
- `src/components/dndState.ts` - module-scoped drag state shared during an active drag.
