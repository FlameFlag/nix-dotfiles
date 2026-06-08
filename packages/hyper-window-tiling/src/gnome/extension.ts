import type Gio from 'gi://Gio';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import { wm } from 'resource:///org/gnome/shell/ui/main.js';
import type { BindingName, CycleBindingName } from '../shared/lib.js';
import {
    advanceCycle,
    CYCLE_BINDING_NAMES,
    CYCLE_LAYOUT_PRESETS,
    createCycleState,
    MAXIMIZE_BINDING_NAME,
} from '../shared/lib.js';
import { resolveLayout } from './layouts.js';
import { focusedWindow } from './windows.js';

export default class HyperWindowTilingExtension extends Extension {
    private settings: Gio.Settings | null = null;
    private cycle = createCycleState();

    enable() {
        this.settings = this.getSettings();
        this.cycle = createCycleState();

        CYCLE_BINDING_NAMES.forEach((bindingName) => {
            this.addKeybinding(bindingName, () => this.applyCycle(bindingName));
        });

        this.addKeybinding(MAXIMIZE_BINDING_NAME, () =>
            this.maximizeFocusedWindow(),
        );
    }

    disable() {
        [...CYCLE_BINDING_NAMES, MAXIMIZE_BINDING_NAME].forEach(
            (bindingName) => {
                wm.removeKeybinding(bindingName);
            },
        );

        this.settings = null;
        this.cycle = createCycleState();
    }

    private addKeybinding(
        bindingName: BindingName,
        handler: Meta.KeyHandlerFunc,
    ) {
        if (!this.settings) return;

        wm.addKeybinding(
            bindingName,
            this.settings,
            Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL,
            handler,
        );
    }

    private applyCycle(bindingName: CycleBindingName) {
        const window = focusedWindow();
        if (!window?.allows_move() || !window.allows_resize()) return;

        const layouts = CYCLE_LAYOUT_PRESETS[bindingName];
        const rect = resolveLayout(
            window,
            layouts[advanceCycle(this.cycle, bindingName, layouts.length)],
        );

        if (window.is_maximized()) window.unmaximize();

        window.move_resize_frame(true, rect.x, rect.y, rect.width, rect.height);
    }

    private maximizeFocusedWindow() {
        const window = focusedWindow();
        if (!window?.allows_move() || !window.allows_resize()) return;

        const rect = resolveLayout(window, 'maximize');
        if (window.is_maximized()) window.unmaximize();

        window.move_resize_frame(true, rect.x, rect.y, rect.width, rect.height);
    }
}
