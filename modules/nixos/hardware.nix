{
  pkgs,
  lib,
  config,
  ...
}:
{

  options.nixOS.nvidia.enable = lib.mkEnableOption "NVIDIA";
  options.nixOS.amd.enable = lib.mkEnableOption "AMD";

  config = lib.mkMerge [
    ({
      # General hardware configuration
      environment.systemPackages = builtins.attrValues { inherit (pkgs) libva-utils; };
      environment.sessionVariables = {
        # It tells supported apps to use the Ozone/Wayland backend
        NIXOS_OZONE_WL = "1";

        # Disables the RDD (Remote Data Decoder) sandbox in Firefox.
        MOZ_DISABLE_RDD_SANDBOX = "1";

        # Hardware cursors are currently broken on wlroots
        WLR_NO_HARDWARE_CURSORS = "1";

        # Improve compatibility for older Java GUI (AWT/Swing) apps, especially on
        # non-reparenting WMs (most Wayland compositors, some X11 WMs)
        _JAVA_AWT_WM_NONREPARENTING = "1";

        # Enable automatic scaling for Qt5/Qt6 applications based on monitor DPI
        # Useful for HiDPI displays
        QT_AUTO_SCREEN_SCALE_FACTOR = "1";

        # Specifies the platform to use for EGL (OpenGL ES) applications.
        # Setting this to "wayland" ensures that EGL-based apps use the Wayland backend.
        EGL_PLATFORM = "wayland";

        # Enable Variable Refresh Rate (VRR/FreeSync) for OpenGL and GLX
        __GL_VRR_ALLOWED = "1";
        __GLX_VRR_ALLOWED = "1";
      };

      hardware.graphics = {
        enable = true;
        enable32Bit = lib.mkIf config.nixpkgs.hostPlatform.isx86_64 true;
        extraPackages = builtins.attrValues {
          inherit (pkgs)
            libva-vdpau-driver
            libvdpau-va-gl
            mesa
            vulkan-loader
            ;
        };
      }
      // lib.optionalAttrs config.nixpkgs.hostPlatform.isx86_64 {
        extraPackages32 = builtins.attrValues {
          inherit (pkgs.pkgsi686Linux) libva-vdpau-driver libvdpau-va-gl mesa;
        };
      };
    })
    (lib.mkIf config.nixOS.nvidia.enable {
      nixpkgs.config.cudaSupport = true;
      boot.extraModprobeConfig =
        "options nvidia "
        + lib.concatStringsSep " " [
          # NVIDIA assumes that by default your CPU doesn't support `PAT`, but this
          # is effectively never the case
          "NVreg_UsePageAttributeTable=1"
          # This is sometimes needed for ddc/ci support, see
          # https://www.ddcutil.com/nvidia/
          "NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100"
        ];
      boot.kernelParams = lib.optional config.powerManagement.enable [
        "nvidia.NVreg_TemporaryFilePath=/var/tmp"
      ];

      environment.sessionVariables = {
        # Required to run the correct GBM backend for NVIDIA GPUs on Wayland
        GBM_BACKEND = "nvidia-drm";
        # Apparently, without this NOUVEAU may attempt to be used instead
        # (despite it being blacklisted)
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";

        NVD_BACKEND = "direct";
        LIBVA_DRIVER_NAME = "nvidia";
      };

      services.xserver.videoDrivers = [ "nvidia" ];

      hardware = {
        nvidia = {
          open = true;
          package = {
            version = "590.48.01";
            sha256_64bit = "sha256-ueL4BpN4FDHMh/TNKRCeEz3Oy1ClDWto1LO/LWlr1ok=";
            sha256_aarch64 = "sha256-FOz7f6pW1NGM2f74kbP6LbNijxKj5ZtZ08bm0aC+/YA=";
            openSha256 = "sha256-hECHfguzwduEfPo5pCDjWE/MjtRDhINVr4b1awFdP44=";
            settingsSha256 = "sha256-NWsqUciPa4f1ZX6f0By3yScz3pqKJV1ei9GvOF8qIEE=";
            persistencedSha256 = "sha256-wsNeuw7IaY6Qc/i/AzT/4N82lPjkwfrhxidKWUtcwW8=";
            useProfiles = true;
          };
          modesetting.enable = true;
          powerManagement.enable = true;
          powerManagement.finegrained = true;
        };

        graphics.extraPackages = builtins.attrValues {
          inherit (pkgs) nv-codec-headers-12;
        };
      };
    })
    (lib.mkIf config.nixOS.amd.enable {
      # HIP libraries support - many applications hard-code HIP library paths
      systemd.tmpfiles.rules =
        let
          rocmEnv = pkgs.symlinkJoin {
            name = "rocm-combined";
            paths = builtins.attrValues {
              inherit (pkgs.pkgs.rocmPackages) rocblas hipblas clr;
            };
          };
        in
        [ "L+    /opt/rocm   -    -    -     -    ${rocmEnv}" ];

      hardware.graphics.extraPackages = builtins.attrValues {
        inherit (pkgs.rocmPackages) clr;
      };
    })
  ];
}
