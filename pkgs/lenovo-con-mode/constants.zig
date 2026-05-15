pub const conservation_mode_path = "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode";
pub const dmi_vendor_path = "/sys/class/dmi/id/sys_vendor";
pub const dmi_board_vendor_path = "/sys/class/dmi/id/board_vendor";
pub const dmi_product_name_path = "/sys/class/dmi/id/product_name";

pub const windows_energy_drv_path = "\\\\.\\EnergyDrv";
pub const windows_energy_ioctl_gbmd_sbmc = 0x831020f8;
pub const windows_gbmd_conservation_state_bit = 5;
pub const windows_sbmc_conservation_on = 3;
pub const windows_sbmc_conservation_off = 5;
pub const windows_sbmc_query_gbmd = 0xff;
