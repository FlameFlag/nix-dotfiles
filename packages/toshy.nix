{
  bash,
  coreutils,
  dbus,
  fetchFromGitHub,
  fetchPypi,
  gawk,
  glib,
  gnugrep,
  gnused,
  gtk3,
  gtk4,
  lib,
  libadwaita,
  libayatana-appindicator,
  libnotify,
  makeWrapper,
  nixosTests ? { },
  procps,
  python3Packages,
  stdenvNoCC,
  systemd,
  wrapGAppsHook4,
  xdg-utils,
  xhost,
  xset,
  zenity,
}:
let
  python = python3Packages.python;

  hyprpy = python3Packages.buildPythonPackage rec {
    pname = "hyprpy";
    version = "0.1.10";
    pyproject = true;

    __structuredAttrs = true;
    strictDeps = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-OX8iOglHMFAwq0LT1cE4nhpP9BxgWFcgc3potqSNIAg=";
    };

    build-system = with python3Packages; [ setuptools ];

    dependencies = with python3Packages; [ pydantic ];

    pythonImportsCheck = [ "hyprpy" ];

    meta = {
      description = "Python bindings for the Hyprland compositor";
      homepage = "https://github.com/ulinja/hyprpy";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  };

  xwaykeyz = python3Packages.buildPythonPackage {
    pname = "xwaykeyz";
    version = "1.22.0";
    pyproject = true;

    __structuredAttrs = true;
    strictDeps = true;

    src = fetchFromGitHub {
      owner = "RedBearAK";
      repo = "xwaykeyz";
      rev = "1615a4dcdcdc3d6d135322cd7401c882e28fbf2b";
      hash = "sha256-Og5IvGo95aafL4dV78hLZACd3FqNfrvWwDMvNa43JwI=";
    };

    build-system = with python3Packages; [ hatchling ];

    dependencies = with python3Packages; [
      anyascii
      appdirs
      dbus-python
      evdev
      hyprpy
      i3ipc
      inotify-simple
      ordered-set
      pywayland
      xlib
    ];

    pythonRelaxDeps = [
      "dbus-python"
      "evdev"
      "hyprpy"
      "inotify-simple"
      "python-xlib"
    ];

    pythonImportsCheck = [ "xwaykeyz" ];

    meta = {
      description = "Linux keymapper for X11 and Wayland, with per-app capability";
      homepage = "https://github.com/RedBearAK/xwaykeyz";
      license = lib.licenses.gpl3Plus;
      mainProgram = "xwaykeyz";
      platforms = lib.platforms.linux;
    };
  };

  pythonPath = python3Packages.makePythonPath [
    python3Packages.dbus-python
    python3Packages.lockfile
    python3Packages.psutil
    python3Packages.pygobject3
    python3Packages.sv-ttk
    python3Packages.systemd-python
    python3Packages.tkinter
    python3Packages.watchdog
    python3Packages.xkbcommon
    xwaykeyz
  ];

  runtimePath = lib.makeBinPath [
    bash
    coreutils
    dbus
    gawk
    glib
    gnugrep
    gnused
    libnotify
    procps
    systemd
    xdg-utils
    xhost
    xset
    zenity
    xwaykeyz
  ];

  nixosModuleMessage = "Toshy systemd services are managed by the nix-dotfiles nixOS.toshy module.";

  wrapper = import ./toshy/wrapper.nix {
    inherit
      bash
      lib
      nixosModuleMessage
      python
      pythonPath
      runtimePath
      systemd
      xwaykeyz
      ;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "toshy";
  version = "26.06.0";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "RedBearAK";
    repo = "Toshy";
    tag = "Toshy_v${finalAttrs.version}";
    hash = "sha256-zFdS5YpGVxkMhhTtAi0iX6ilc+xRw8xWYGtceMjXx9w=";
  };

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk3
    gtk4
    libadwaita
    libayatana-appindicator
  ];

  dontWrapGApps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/scalable/apps" \
      "$out/share/toshy" \
      "$out/share/toshy/nix-dotfiles"

    cp -r \
      assets \
      cosmic-dbus-service \
      default-toshy-config \
      kwin-dbus-service \
      kwin-script \
      scripts \
      toshy_common \
      toshy_gui \
      wlroots-dbus-service \
      toshy_layout_selector.py \
      toshy_tray.py \
      "$out/share/toshy/"

    ${python.interpreter} ${./toshy/merge-slices.py} \
      "$out/share/toshy/default-toshy-config/toshy_config_barebones.py" \
      ${./toshy/slices} \
      "$out/share/toshy/nix-dotfiles/toshy_config.py"

    for icon in toshy_app_icon_rainbow toshy_app_icon_rainbow_inverse toshy_app_icon_rainbow_inverse_grayscale; do
      install -Dm644 "assets/$icon.svg" "$out/share/icons/hicolor/scalable/apps/$icon.svg"
    done

    install -Dm644 desktop/app.toshy.preferences.desktop "$out/share/applications/app.toshy.preferences.desktop"
    install -Dm644 desktop/Toshy_Tray.desktop "$out/share/applications/Toshy_Tray.desktop"
    substituteInPlace "$out/share/applications/app.toshy.preferences.desktop" \
      --replace-fail 'Exec=$HOME/.local/bin/toshy-gui' "Exec=$out/bin/toshy-gui" \
      --replace-fail 'NoDisplay=false' 'NoDisplay=true'
    substituteInPlace "$out/share/applications/Toshy_Tray.desktop" \
      --replace-fail 'Exec=$HOME/.local/bin/toshy-tray' "Exec=$out/bin/toshy-tray" \
      --replace-fail 'NoDisplay=false' 'NoDisplay=true'

    substituteInPlace "$out/share/toshy/toshy_common/service_manager.py" \
      --replace-fail "self.home_local_bin = os.path.join(self.home_dir, '.local', 'bin')" "self.home_local_bin = '$out/bin'" \
      --replace-fail 'enable_cmd_base = ["systemctl", "--user", "enable"]' 'enable_cmd_base = ["true"]' \
      --replace-fail 'disable_cmd_base = ["systemctl", "--user", "disable"]' 'disable_cmd_base = ["true"]' \
      --replace-fail 'message = "Toshy services ENABLED. Will autostart at login."' 'message = "${nixosModuleMessage}"' \
      --replace-fail 'message = "Toshy systemd services DISABLED. Will not autostart."' 'message = "${nixosModuleMessage}"'

    substituteInPlace "$out/share/toshy/scripts/tshysvc-config" \
      --replace-fail 'export PATH=$HOME/.local/bin:$PATH' 'export PATH=${runtimePath}:$PATH' \
      --replace-fail 'source "$HOME/.config/toshy/.venv/bin/activate"' true \
      --replace-fail 'xwaykeyz -w -c "$HOME/.config/toshy/toshy_config.py"' '${lib.getExe xwaykeyz} -w -c "''${TOSHY_CONFIG_FILE:-$HOME/.config/toshy/toshy_config.py}"'

    ${wrapper.installCommands}

    ln -s toshy-config-start-verbose "$out/bin/toshy-config-verbose-start"
    ln -s toshy-config-start-verbose "$out/bin/toshy-debug"

    makeWrapper ${lib.getExe xwaykeyz} "$out/bin/toshy-devices" \
      --prefix PATH : "${runtimePath}" \
      --add-flags "--list-devices"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    for program in ${lib.escapeShellArgs wrapper.checkedPrograms}; do
      test -x "$out/bin/$program"
    done

    grep -qF "Exec=$out/bin/toshy-gui" "$out/share/applications/app.toshy.preferences.desktop"
    grep -qF "Exec=$out/bin/toshy-tray" "$out/share/applications/Toshy_Tray.desktop"
    grep -qF "NoDisplay=true" "$out/share/applications/app.toshy.preferences.desktop"
    grep -qF "NoDisplay=true" "$out/share/applications/Toshy_Tray.desktop"
    grep -qF "$out/share/toshy" "$out/bin/toshy-config"
    grep -qF "$out/share/toshy/scripts/bin/toshy-services-restart.sh" "$out/bin/toshy-services-restart"
    grep -qF "TOSHY_CONFIG_FILE" "$out/share/toshy/scripts/tshysvc-config"
    grep -qF "Toshy Barebones Config" "$out/share/toshy/nix-dotfiles/toshy_config.py"
    grep -qF "NIX_DOTFILES_TOSHY_ONLY_DEVICES" "$out/share/toshy/nix-dotfiles/toshy_config.py"
    grep -qF "SLICE_MARK_START: keymapper_api" "$out/share/toshy/nix-dotfiles/toshy_config.py"
    grep -qF "SLICE_MARK_START: barebones_user_cfg" "$out/share/toshy/nix-dotfiles/toshy_config.py"
    grep -qF "toshy_kwin_script_setup.py" "$out/bin/toshy-kwin-dbus-service"
    grep -qF "${nixosModuleMessage}" "$out/bin/toshy-services-enable"
    grep -qF "self.home_local_bin = '$out/bin'" "$out/share/toshy/toshy_common/service_manager.py"
    grep -qF 'enable_cmd_base = ["true"]' "$out/share/toshy/toshy_common/service_manager.py"
    test -f "$out/share/toshy/kwin-script/kde5_kde6_merged/toshy-dbus-notifyactivewindow/contents/code/main.js"

    runHook postInstallCheck
  '';

  passthru = {
    inherit xwaykeyz;
  }
  // lib.optionalAttrs (nixosTests ? toshy) {
    tests.nixos = nixosTests.toshy;
  };

  meta = {
    description = "Desktop key remapper for Linux that makes shortcuts behave like macOS";
    homepage = "https://github.com/RedBearAK/Toshy";
    license = lib.licenses.gpl3Plus;
    mainProgram = "toshy-gui";
    platforms = lib.platforms.linux;
  };
})
