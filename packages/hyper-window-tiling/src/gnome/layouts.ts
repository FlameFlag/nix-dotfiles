import type Meta from 'gi://Meta';
import Mtk from 'gi://Mtk';
import type { LayoutPreset } from '../shared/lib.js';
import { resolveLayoutPresetRect } from '../shared/lib.js';

export function resolveLayout(window: Meta.Window, preset: LayoutPreset) {
    const workArea = window.get_work_area_current_monitor();
    const rect = resolveLayoutPresetRect(
        workArea,
        window.get_frame_rect(),
        preset,
    );

    return Mtk.Rectangle.new(rect.x, rect.y, rect.width, rect.height);
}
