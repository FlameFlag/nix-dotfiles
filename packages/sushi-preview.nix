{
  blueprint-compiler,
  fetchFromGitLab,
  freetype,
  fribidi,
  gjs,
  glib,
  glycin-loaders,
  gobject-introspection,
  gst_all_1,
  gtk4,
  gtksourceview5,
  harfbuzz,
  lib,
  libadwaita,
  libglycin,
  libglycin-gtk4,
  libx11,
  meson,
  ninja,
  papers,
  pkg-config,
  stdenv,
  webkitgtk_6_0,
  wrapGAppsHook4,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "sushi-preview";
  version = "51.alpha-${builtins.substring 0 8 finalAttrs.sushiRev}";

  sushiRev = "db55853ec62bc1393bfd455d82ddbc8d7b877f90";

  src = fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "GNOME";
    repo = "sushi";
    rev = finalAttrs.sushiRev;
    hash = "sha256-AWh8hjq4b1jisW2KrplePFX32Y+B1Vhiyp3CvXmISYA=";
  };

  # 0001-0012 are GNOME/sushi!96, exported with git format-patch from:
  # https://gitlab.gnome.org/GNOME/sushi/-/merge_requests/96
  mr96Patches = [
    ./sushi/patches/0001-renderer-Drop-unused-ResizePolicy.patch
    ./sushi/patches/0002-main-window-Simplify-full-window-size.patch
    ./sushi/patches/0003-main-window-Detect-user-scaling.patch
    ./sushi/patches/0004-main-window-Set-minimum-size-via-window.patch
    ./sushi/patches/0005-general-Propagate-natural-size-when-scrollable.patch
    ./sushi/patches/0006-general-Drop-unused-constants-file.patch
    ./sushi/patches/0007-main-window-Cap-natural-size-by-max-size.patch
    ./sushi/patches/0008-main-window-Move-content-size-to-helper-function.patch
    ./sushi/patches/0009-main-window-Inline-content-scaling.patch
    ./sushi/patches/0010-video-Use-scaled-resize-policy.patch
    ./sushi/patches/0011-main-window-Add-StatusPage-resize-policy.patch
    ./sushi/patches/0012-main-window-Fix-error-renderer-resizing.patch
  ];

  # Local source fixes on top of MR !96. The Flatpak app-id patch is intentionally
  # not included in this native Nix package.
  localPatches = [
    ./sushi/patches/0014-main-Use-synchronous-GApplication-run.patch
    ./sushi/patches/0015-main-window-Delay-resize-until-surface-exists.patch
    ./sushi/patches/0016-image-Use-Gdk.Texture-fallback-before-glycin.patch
  ];

  patches = finalAttrs.mr96Patches ++ finalAttrs.localPatches;

  nativeBuildInputs = [
    blueprint-compiler
    gjs
    gobject-introspection
    meson
    ninja
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    freetype
    fribidi
    glib
    gtk4
    gtksourceview5
    harfbuzz
    libadwaita
    libglycin
    libglycin.setupHook
    libglycin-gtk4
    papers
    webkitgtk_6_0
    libx11
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-plugins-ugly
    gst_all_1.gst-plugins-rs
  ];

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix XDG_DATA_DIRS : "${glycin-loaders}/share"
    )
  '';

  passthru = {
    upstreamMergeRequest = "https://gitlab.gnome.org/GNOME/sushi/-/merge_requests/96";
  };

  meta = {
    homepage = "https://gitlab.gnome.org/GNOME/sushi";
    description = "Patched GNOME Sushi/NautilusPreviewer previewer";
    mainProgram = "sushi";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
    teams = [ lib.teams.gnome ];
  };
})
