import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import UPowerGlib from 'gi://UPowerGlib?version=1.0';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {
    QuickMenuToggle,
    SystemIndicator,
} from 'resource:///org/gnome/shell/ui/quickSettings.js';

const DEVICE_KINDS = new Set<number>([
    UPowerGlib.DeviceKind.MOUSE,
    UPowerGlib.DeviceKind.KEYBOARD,
    UPowerGlib.DeviceKind.GAMING_INPUT,
]);
const DEVICE_NOTIFY_SIGNALS = [
    'notify::battery-level',
    'notify::icon-name',
    'notify::is-present',
    'notify::kind',
    'notify::model',
    'notify::native-path',
    'notify::percentage',
    'notify::state',
    'notify::vendor',
    'notify::warning-level',
] as const;
const LOGITECH_HIDPP_POLL_SECONDS = 60;
const LOGITECH_HIDPP_HELPER_TIMEOUT_SECONDS = 3;
const STEELSERIES_HELPER_TIMEOUT_SECONDS = 5;
const STEELSERIES_POLL_SECONDS = 30;

type Device = UPowerGlib.Device;
type SignalConnection = {
    object: GObject.Object;
    id: number;
};
type ExternalPollResult = {
    ok: boolean;
    stdout: string;
};
type ExternalPollHandle = {
    cancel(): void;
};
type DeviceSummary = {
    path: string;
    name: string;
    kind: string;
    iconName: string;
    status: string;
    percentage: number | null;
    level: number;
};
type ExternalDevice = {
    path?: unknown;
    name?: unknown;
    kind?: unknown;
    percentage?: unknown;
    charging?: unknown;
    state?: unknown;
};
type QuickSettings = typeof Main.panel.statusArea.quickSettings & {
    addExternalIndicator(indicator: SystemIndicator, colSpan?: number): void;
};
type QuickMenuToggleParams = Partial<
    ConstructorParameters<typeof QuickMenuToggle>[0]
> & {
    iconName: string;
    menuButtonAccessibleName: string;
    toggleMode: boolean;
};

export default class LogitechBatteryExtension extends Extension {
    private indicator: SystemIndicator | null = null;

    enable() {
        this.indicator = new LogitechBatteryIndicator();
        (
            Main.panel.statusArea.quickSettings as QuickSettings
        ).addExternalIndicator(this.indicator, 2);
    }

    disable() {
        this.indicator?.destroy();
        this.indicator = null;
    }
}

const LogitechBatteryIndicator = GObject.registerClass(
    class LogitechBatteryIndicator extends SystemIndicator {
        private readonly toggle = new QuickMenuToggle({
            title: 'Device Battery',
            subtitle: 'No devices',
            iconName: 'battery-missing-symbolic',
            menuButtonAccessibleName: 'Open device battery menu',
            toggleMode: false,
        } as QuickMenuToggleParams);
        private readonly client = UPowerGlib.Client.new();
        private readonly clientSignals: SignalConnection[] = [];
        private readonly deviceSignals = new Map<string, SignalConnection[]>();
        private logitechHidppDevices: DeviceSummary[] = [];
        private logitechHidppPollId: number | null = null;
        private logitechHidppRequestPending = false;
        private steelseriesDevices: DeviceSummary[] = [];
        private steelseriesPollId: number | null = null;
        private steelseriesRequestPending = false;
        private readonly activeExternalPolls = new Set<ExternalPollHandle>();
        private destroyed = false;

        constructor() {
            super();

            this.quickSettingsItems.push(this.toggle);

            this.clientSignals.push(
                {
                    object: this.client,
                    id: this.client.connect('device-added', (_client, device) =>
                        this.trackDevice(device),
                    ),
                },
                {
                    object: this.client,
                    id: this.client.connect('device-removed', (_client, path) =>
                        this.untrackDevice(path),
                    ),
                },
            );

            for (const device of this.client.get_devices()) {
                this.trackDevice(device);
            }
            this.startLogitechHidppPolling();
            this.startSteelSeriesPolling();
            this.sync();
        }

        override destroy() {
            this.destroyed = true;
            if (this.logitechHidppPollId !== null) {
                GLib.Source.remove(this.logitechHidppPollId);
                this.logitechHidppPollId = null;
            }
            if (this.steelseriesPollId !== null) {
                GLib.Source.remove(this.steelseriesPollId);
                this.steelseriesPollId = null;
            }
            for (const poll of this.activeExternalPolls) {
                poll.cancel();
            }
            this.activeExternalPolls.clear();

            for (const connection of this.clientSignals) {
                connection.object.disconnect(connection.id);
            }
            this.clientSignals.length = 0;

            for (const connections of this.deviceSignals.values()) {
                for (const connection of connections) {
                    connection.object.disconnect(connection.id);
                }
            }
            this.deviceSignals.clear();

            for (const item of this.quickSettingsItems) {
                item.menu?.destroy();
                item.destroy();
            }
            this.quickSettingsItems.length = 0;
            super.destroy();
        }

        private trackDevice(device: Device) {
            const path = device.get_object_path();
            if (this.deviceSignals.has(path)) {
                this.sync();
                return;
            }

            this.deviceSignals.set(
                path,
                DEVICE_NOTIFY_SIGNALS.map((signal) => ({
                    object: device,
                    id: device.connect(signal, () => this.sync()),
                })),
            );
            this.sync();
        }

        private untrackDevice(path: string) {
            const connections = this.deviceSignals.get(path);
            if (!connections) return;

            for (const connection of connections) {
                connection.object.disconnect(connection.id);
            }
            this.deviceSignals.delete(path);
            this.sync();
        }

        private sync() {
            const devices = mergeDeviceSummaries(
                this.client
                    .get_devices()
                    .filter(isLogitechInputDevice)
                    .map(summarizeDevice),
                [...this.logitechHidppDevices, ...this.steelseriesDevices],
            ).sort(compareDeviceSummaries);
            const lowest = lowestDevice(devices);
            const subtitle = summarizeDevices(devices);
            const iconName = lowest
                ? iconForLevel(lowest.level)
                : 'battery-missing-symbolic';

            this.toggle.visible = devices.length > 0;
            this.toggle.iconName = iconName;
            this.toggle.title = 'Device Battery';
            this.toggle.subtitle = subtitle;
            this.toggle.menu.setHeader(iconName, 'Device Battery', subtitle);
            this.toggle.menu.removeAll();

            if (devices.length === 0) {
                this.toggle.menu.addMenuItem(
                    new PopupMenu.PopupMenuItem(
                        'No mouse or keyboard batteries',
                        {
                            reactive: false,
                            can_focus: false,
                        },
                    ),
                );
                return;
            }

            for (const device of devices) {
                this.toggle.menu.addMenuItem(
                    new PopupMenu.PopupImageMenuItem(
                        menuItemLabel(device),
                        device.iconName,
                        {
                            reactive: false,
                            activate: false,
                            hover: false,
                            style_class: null,
                            can_focus: false,
                        },
                    ),
                );
            }
        }

        private startLogitechHidppPolling() {
            this.refreshLogitechHidppDevices();
            this.logitechHidppPollId = GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                LOGITECH_HIDPP_POLL_SECONDS,
                () => {
                    this.refreshLogitechHidppDevices();
                    return GLib.SOURCE_CONTINUE;
                },
            );
        }

        private refreshLogitechHidppDevices() {
            if (this.logitechHidppRequestPending) return;

            this.logitechHidppRequestPending = true;
            let poll: ExternalPollHandle | null = null;
            try {
                const homeDir = GLib.get_home_dir();
                const userHelper = GLib.build_filenamev([
                    homeDir,
                    '.local',
                    'bin',
                    'logitech-hidpp-battery',
                ]);
                const helper = GLib.file_test(
                    userHelper,
                    GLib.FileTest.IS_EXECUTABLE,
                )
                    ? userHelper
                    : 'logitech-hidpp-battery';
                poll = runExternalPoll(
                    [helper, '--json'],
                    LOGITECH_HIDPP_HELPER_TIMEOUT_SECONDS,
                    (result) => {
                        if (poll) this.activeExternalPolls.delete(poll);
                        if (this.destroyed) return;

                        this.logitechHidppDevices = result.ok
                            ? parseExternalDevices(result.stdout)
                            : [];
                        this.logitechHidppRequestPending = false;
                        this.sync();
                    },
                );
                this.activeExternalPolls.add(poll);
            } catch {
                this.logitechHidppDevices = [];
                this.logitechHidppRequestPending = false;
                this.sync();
            }
        }

        private startSteelSeriesPolling() {
            this.refreshSteelSeriesDevices();
            this.steelseriesPollId = GLib.timeout_add_seconds(
                GLib.PRIORITY_DEFAULT,
                STEELSERIES_POLL_SECONDS,
                () => {
                    this.refreshSteelSeriesDevices();
                    return GLib.SOURCE_CONTINUE;
                },
            );
        }

        private refreshSteelSeriesDevices() {
            if (this.steelseriesRequestPending) return;

            this.steelseriesRequestPending = true;
            let poll: ExternalPollHandle | null = null;
            try {
                const homeDir = GLib.get_home_dir();
                const userHelper = GLib.build_filenamev([
                    homeDir,
                    '.local',
                    'bin',
                    'steelseries-arctis-battery',
                ]);
                const helper = GLib.file_test(
                    userHelper,
                    GLib.FileTest.IS_EXECUTABLE,
                )
                    ? userHelper
                    : 'steelseries-arctis-battery';
                poll = runExternalPoll(
                    [helper, '--json'],
                    STEELSERIES_HELPER_TIMEOUT_SECONDS,
                    (result) => {
                        if (poll) this.activeExternalPolls.delete(poll);
                        if (this.destroyed) return;

                        this.steelseriesDevices = result.ok
                            ? parseExternalDevices(result.stdout)
                            : [];
                        this.steelseriesRequestPending = false;
                        this.sync();
                    },
                );
                this.activeExternalPolls.add(poll);
            } catch {
                this.steelseriesDevices = [];
                this.steelseriesRequestPending = false;
                this.sync();
            }
        }
    },
) as unknown as { new (): SystemIndicator };

function runExternalPoll(
    argv: string[],
    timeoutSeconds: number,
    callback: (result: ExternalPollResult) => void,
): ExternalPollHandle {
    const process = Gio.Subprocess.new(
        argv,
        Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
    );
    const cancellable = new Gio.Cancellable();
    let timeoutId: number | null = GLib.timeout_add_seconds(
        GLib.PRIORITY_DEFAULT,
        timeoutSeconds,
        () => {
            timeoutId = null;
            cancelProcess();
            return GLib.SOURCE_REMOVE;
        },
    );

    process.communicate_utf8_async(null, cancellable, (_process, result) => {
        if (timeoutId !== null) {
            GLib.Source.remove(timeoutId);
            timeoutId = null;
        }

        try {
            const [ok, stdout] = process.communicate_utf8_finish(result);
            callback({ ok: ok && process.get_successful(), stdout });
        } catch {
            callback({ ok: false, stdout: '' });
        }
    });

    const cancel = () => {
        if (timeoutId !== null) {
            GLib.Source.remove(timeoutId);
            timeoutId = null;
        }
        cancelProcess();
    };

    const cancelProcess = () => {
        if (!cancellable.is_cancelled()) {
            cancellable.cancel();
        }
        process.force_exit();
    };

    return { cancel };
}

function isLogitechInputDevice(device: Device): boolean {
    return device.isPresent && DEVICE_KINDS.has(device.kind);
}

function summarizeDevice(device: Device): DeviceSummary {
    const percentage = normalizedPercentage(device.percentage);
    const kind = kindLabel(device.kind);
    const level = numericLevel(device, percentage);
    return {
        path: device.get_object_path(),
        name: device.model || `${device.vendor || 'Logitech'} ${kind}`,
        kind,
        iconName: iconForLevel(level),
        status:
            percentage === null
                ? levelLabel(device.batteryLevel)
                : `${percentage}%`,
        percentage,
        level,
    };
}

function normalizedPercentage(percentage: number): number | null {
    if (!Number.isFinite(percentage) || percentage < 0 || percentage > 100) {
        return null;
    }

    return Math.round(percentage);
}

function numericLevel(device: Device, percentage: number | null): number {
    if (percentage !== null) {
        return percentage;
    }

    switch (device.batteryLevel) {
        case UPowerGlib.DeviceLevel.FULL:
            return 100;
        case UPowerGlib.DeviceLevel.HIGH:
            return 75;
        case UPowerGlib.DeviceLevel.NORMAL:
            return 50;
        case UPowerGlib.DeviceLevel.LOW:
            return 20;
        case UPowerGlib.DeviceLevel.CRITICAL:
            return 5;
        default:
            return 0;
    }
}

function levelLabel(level: number): string {
    switch (level) {
        case UPowerGlib.DeviceLevel.FULL:
            return 'Full';
        case UPowerGlib.DeviceLevel.HIGH:
            return 'High';
        case UPowerGlib.DeviceLevel.NORMAL:
            return 'Normal';
        case UPowerGlib.DeviceLevel.LOW:
            return 'Low';
        case UPowerGlib.DeviceLevel.CRITICAL:
            return 'Critical';
        default:
            return 'Unknown';
    }
}

function kindLabel(kind: number): string {
    switch (kind) {
        case UPowerGlib.DeviceKind.KEYBOARD:
            return 'Keyboard';
        case UPowerGlib.DeviceKind.MOUSE:
            return 'Mouse';
        case UPowerGlib.DeviceKind.GAMING_INPUT:
            return 'Controller';
        default:
            return 'Device';
    }
}

function iconForLevel(level: number): string {
    if (level <= 10) {
        return 'battery-caution-symbolic';
    }
    if (level <= 30) {
        return 'battery-low-symbolic';
    }
    if (level <= 60) {
        return 'battery-good-symbolic';
    }

    return 'battery-full-symbolic';
}

function summarizeDevices(devices: DeviceSummary[]): string {
    if (devices.length === 0) {
        return 'No devices';
    }

    return devices
        .map((device) => `${device.kind} ${device.status}`)
        .join(', ');
}

function menuItemLabel(device: DeviceSummary): string {
    return `${device.status}  ${shortDeviceName(device)}`;
}

function shortDeviceName(device: DeviceSummary): string {
    const normalized = device.name.toLocaleLowerCase();
    if (normalized.includes('arctis nova pro')) {
        return normalized.includes('spare')
            ? 'Nova Pro Spare'
            : 'Nova Pro Headset';
    }
    if (normalized.includes('lift vertical ergonomic mouse')) {
        return 'Lift Mouse';
    }
    if (normalized.includes('pebble keys 2 k380s')) {
        return 'Pebble K380s';
    }
    if (normalized.includes('pebble k380s')) {
        return 'Pebble K380s';
    }

    return device.name;
}

function lowestDevice(devices: DeviceSummary[]): DeviceSummary | null {
    return devices.reduce<DeviceSummary | null>((lowest, device) => {
        if (!lowest || device.level < lowest.level) {
            return device;
        }

        return lowest;
    }, null);
}

function compareDeviceSummaries(a: DeviceSummary, b: DeviceSummary): number {
    return a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name);
}

function mergeDeviceSummaries(
    upowerDevices: DeviceSummary[],
    externalDevices: DeviceSummary[],
): DeviceSummary[] {
    const devices = [...upowerDevices];
    const upowerKeys = new Set(upowerDevices.map(deviceMergeKey));

    for (const device of externalDevices) {
        if (!upowerKeys.has(deviceMergeKey(device))) {
            devices.push(device);
        }
    }

    return devices;
}

function deviceMergeKey(device: DeviceSummary): string {
    return `${device.kind}:${shortDeviceName(device).toLocaleLowerCase()}`;
}

function parseExternalDevices(output: string): DeviceSummary[] {
    let devices: unknown;
    try {
        devices = JSON.parse(output);
    } catch {
        return [];
    }

    if (!Array.isArray(devices)) {
        return [];
    }

    return devices.flatMap((device) => summarizeExternalDevice(device));
}

function summarizeExternalDevice(device: unknown): DeviceSummary[] {
    if (!device || typeof device !== 'object') {
        return [];
    }

    const external = device as ExternalDevice;
    const percentage =
        typeof external.percentage === 'number'
            ? normalizedPercentage(external.percentage)
            : null;
    if (percentage === null) {
        return [];
    }

    const name =
        typeof external.name === 'string' && external.name.trim()
            ? external.name.trim()
            : 'External Device';
    const kind =
        typeof external.kind === 'string' && external.kind.trim()
            ? external.kind.trim()
            : 'Headset';
    const status = externalDeviceStatus(percentage, external);

    return [
        {
            path:
                typeof external.path === 'string' && external.path.trim()
                    ? external.path.trim()
                    : `external:${name}`,
            name,
            kind,
            iconName: iconForLevel(percentage),
            status,
            percentage,
            level: percentage,
        },
    ];
}

function externalDeviceStatus(
    percentage: number,
    external: ExternalDevice,
): string {
    const stateLabel =
        typeof external.state === 'string'
            ? externalStateLabel(external.state)
            : null;
    if (stateLabel) {
        return `${percentage}% ${stateLabel}`;
    }
    if (external.charging === true) {
        return `${percentage}% Charging`;
    }

    return `${percentage}%`;
}

function externalStateLabel(state: string): string | null {
    switch (state.trim().toLocaleLowerCase()) {
        case 'available':
            return 'Available';
        case 'charging':
            return 'Charging';
        case 'online':
            return null;
        default:
            return null;
    }
}
