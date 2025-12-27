_: {
  systemd = {
    services = {
      lenovo-con-mode = {
        description = "Toggle Lenovo Conservation Mode (60% ↔ 100%)";
        enable = true;
        serviceConfig.Type = "oneshot";
        script = ''
          CURRENT=$(cat /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode)
          if [ "$CURRENT" = "1" ]; then
            echo 0 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
            echo "Conservation Mode: DISABLED (100% charge)"
          else
            echo 1 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
            echo "Conservation Mode: ENABLED (60% charge)"
          fi
        '';
        startLimitBurst = 5;
        startLimitIntervalSec = 10;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
