import Meta from 'gi://Meta';
import type Mtk from 'gi://Mtk';

const IGNORED_WINDOW_TYPES = new Set([
    Meta.WindowType.DESKTOP,
    Meta.WindowType.DOCK,
]);

export function focusedWindow() {
    const window = global.display.focus_window;
    if (!window) return null;

    return [
        window.is_override_redirect(),
        window.is_fullscreen(),
        window.is_skip_taskbar(),
        IGNORED_WINDOW_TYPES.has(window.get_window_type()),
    ].some(Boolean)
        ? null
        : window;
}

export function canMoveResizeWindow(window: Meta.Window) {
    if (window.get_maximize_flags()) {
        return window.can_maximize();
    }

    return window.allows_move() && window.allows_resize();
}

export function moveResizeWindow(window: Meta.Window, rect: Mtk.Rectangle) {
    if (window.get_maximize_flags()) {
        window.set_unmaximize_flags(Meta.MaximizeFlags.BOTH);
        window.unmaximize();
    }

    window.move_resize_frame(true, rect.x, rect.y, rect.width, rect.height);
}
