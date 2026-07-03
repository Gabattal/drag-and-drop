type TDragState = {
    data: unknown;
    dropRect: DOMRect | null;
    element: HTMLElement;
    group: string;
    height: number;
    id: string;
    placeholder: HTMLElement | null;
    sourceIndex: number;
    sourceRect: DOMRect;
    sourceZoneId: string;
    width: number;
};

let current: TDragState | null = null;

export const dndState = {
    end(): void {
        current = null;
    },
    get(): TDragState | null {
        return current;
    },
    setDropRect(rect: DOMRect | null): void {
        if (current) current.dropRect = rect;
    },
    setPlaceholder(placeholder: HTMLElement | null): void {
        if (current) current.placeholder = placeholder;
    },
    start(state: Omit<TDragState, "dropRect" | "placeholder">): void {
        current = { ...state, dropRect: null, placeholder: null };
    }
};
