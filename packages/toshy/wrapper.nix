{
  bash,
  lib,
  nixosModuleMessage,
  python,
  pythonPath,
  runtimePath,
  systemd,
  xwaykeyz,
}:
let
  pythonPrograms = {
    toshy-gui = "-m toshy_gui";
    toshy-tray = "$out/share/toshy/toshy_tray.py";
    toshy-env = "$out/share/toshy/toshy_common/env_context.py";
    toshy-machine-id = "$out/share/toshy/toshy_common/machine_context.py";
    toshy-versions = "$out/share/toshy/scripts/toshy_versions.py";
    toshy-xkb-check = "$out/share/toshy/toshy_common/xkb_check.py";
    toshy-kblayout-check = "-m toshy_common.kblayout_context";
  };

  scriptWrappers = {
    toshy-config = "$out/share/toshy/scripts/tshysvc-config";
    toshy-session-monitor = "$out/share/toshy/scripts/tshysvc-sessmon";
    toshy-services-start = "$out/share/toshy/scripts/bin/toshy-services-start.sh";
    toshy-services-stop = "$out/share/toshy/scripts/bin/toshy-services-stop.sh";
    toshy-services-restart = "$out/share/toshy/scripts/bin/toshy-services-restart.sh";
    toshy-services-status = "$out/share/toshy/scripts/bin/toshy-services-status.sh";
    toshy-services-log = "$out/share/toshy/scripts/bin/toshy-services-log.sh";
  };

  systemctlWrappers = {
    toshy-config-start = "start toshy-config.service";
    toshy-config-stop = "stop toshy-config.service";
    toshy-config-restart = "restart toshy-config.service";
  };

  moduleManagedCommands = [
    "toshy-services-enable"
    "toshy-services-disable"
    "toshy-systemd-setup"
    "toshy-systemd-setup-debug"
    "toshy-systemd-remove"
  ];

  makePythonWrapper = name: target: ''
    makeWrapper ${python.interpreter} "$out/bin/${name}" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$out/share/toshy:${pythonPath}" \
      --add-flags "${target}"
  '';

  makeDbusWrapper = name: processName: target: preExec: ''
    makeShellWrapper ${bash}/bin/bash "$out/bin/${name}" \
      "''${gappsWrapperArgs[@]}" \
      --set TOSHY_SHARE "$out/share/toshy" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$out/share/toshy:${pythonPath}" \
      --add-flag "-c" \
      --add-flag ${lib.escapeShellArg ''
        pkill -f ${processName} || true
        sleep 0.5
        ${preExec}
        exec ${python.interpreter} -u "''${TOSHY_SHARE}/${target}"
      ''}
  '';

  makeScriptWrapper = name: target: ''
    makeShellWrapper ${bash}/bin/bash "$out/bin/${name}" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$out/share/toshy:${pythonPath}" \
      --add-flag "${target}"
  '';

  makeSystemctlWrapper = name: args: ''
    makeWrapper ${lib.getExe' systemd "systemctl"} "$out/bin/${name}" \
      --add-flags "--user ${args}"
  '';

  makeModuleManagedCommand = program: ''
    makeShellWrapper ${bash}/bin/bash "$out/bin/${program}" \
      --add-flag "-c" \
      --add-flag "echo '${nixosModuleMessage}'"
  '';

  makeVerboseConfigRunner = ''
    makeShellWrapper ${bash}/bin/bash "$out/bin/toshy-config-start-verbose" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$out/share/toshy:${pythonPath}" \
      --add-flag "-c" \
      --add-flag ${lib.escapeShellArg ''
        systemctl --user stop toshy-config.service >/dev/null 2>&1 || true
        pkill -f 'bin/xwaykeyz' || true
        pkill -f 'bin/keyszer' || true
        pkill -f 'bin/xkeysnail' || true

        if command -v xhost >/dev/null 2>&1 && [ "''${XDG_SESSION_TYPE:-}" = x11 ]; then
          xhost +local:
        fi

        exec ${lib.getExe xwaykeyz} --flush -w -v -c "''${TOSHY_CONFIG_FILE:-''${HOME}/.config/toshy/toshy_config.py}"
      ''}
  '';
in
{
  checkedPrograms =
    builtins.attrNames pythonPrograms
    ++ builtins.attrNames scriptWrappers
    ++ builtins.attrNames systemctlWrappers
    ++ moduleManagedCommands
    ++ [
      "toshy-config-start-verbose"
      "toshy-cosmic-dbus-service"
      "toshy-debug"
      "toshy-devices"
      "toshy-kwin-dbus-service"
      "toshy-wlroots-dbus-service"
    ];

  installCommands = ''
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList makePythonWrapper pythonPrograms)}
    ${makeVerboseConfigRunner}
    ${makeDbusWrapper "toshy-kwin-dbus-service" "toshy_kwin_dbus_service"
      "kwin-dbus-service/toshy_kwin_dbus_service.py"
      ''
        nohup ${python.interpreter} -u "''${TOSHY_SHARE}/kwin-dbus-service/toshy_kwin_script_setup.py" >/dev/null 2>&1 &
      ''
    }
    ${makeDbusWrapper "toshy-cosmic-dbus-service" "toshy_cosmic_dbus_service"
      "cosmic-dbus-service/toshy_cosmic_dbus_service.py"
      ""
    }
    ${makeDbusWrapper "toshy-wlroots-dbus-service" "toshy_wlroots_dbus_service"
      "wlroots-dbus-service/toshy_wlroots_dbus_service.py"
      ""
    }
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList makeScriptWrapper scriptWrappers)}
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList makeSystemctlWrapper systemctlWrappers)}
    ${lib.concatMapStringsSep "\n" makeModuleManagedCommand moduleManagedCommands}
  '';
}
