import Meta from 'gi://Meta';

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
