_: {
  systemd = {
    services = {
      # Set 60% Charging limit to "conserve" battery life
      conserveModeEnable = {
        description = "Enable Lenovo Conservation Mode";
        enable = true;
        serviceConfig.Type = "oneshot";
        script = "echo 1 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode";
        wantedBy = [ "multi-user.target" ];
      };
      # Disable "Conserve" Mode and let battery charge to 100%;
      conserveModeDisable = {
        description = "Disable Lenovo Conservation Mode";
        enable = false;
        serviceConfig.Type = "oneshot";
        script = "echo 0 > /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode";
      };
    };
  };
}
