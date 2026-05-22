use crate::{Error, Result};

#[cfg(target_os = "linux")]
pub const CONSERVATION_MODE_PATH: &str =
    "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode";
#[cfg(target_os = "linux")]
const DMI_VENDOR_PATH: &str = "/sys/class/dmi/id/sys_vendor";
#[cfg(target_os = "linux")]
const DMI_BOARD_VENDOR_PATH: &str = "/sys/class/dmi/id/board_vendor";
#[cfg(target_os = "linux")]
const DMI_PRODUCT_NAME_PATH: &str = "/sys/class/dmi/id/product_name";

#[cfg(target_os = "linux")]
pub fn is_supported_lenovo() -> Result<bool> {
    if !is_lenovo_machine() {
        return Ok(false);
    }
    match fs_err::metadata(CONSERVATION_MODE_PATH) {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) if err.kind() == std::io::ErrorKind::PermissionDenied => Ok(true),
        Err(err) => Err(err.into()),
    }
}

#[cfg(target_os = "linux")]
fn is_lenovo_machine() -> bool {
    [
        DMI_VENDOR_PATH,
        DMI_BOARD_VENDOR_PATH,
        DMI_PRODUCT_NAME_PATH,
    ]
    .iter()
    .filter_map(|path| fs_err::read_to_string(path).ok())
    .map(|value| value.trim().to_ascii_lowercase())
    .any(|value| value.contains("lenovo") || value.contains("legion"))
}

#[cfg(target_os = "linux")]
pub fn read_mode() -> Result<bool> {
    let text = fs_err::read_to_string(CONSERVATION_MODE_PATH).map_err(map_linux_node_error)?;
    parse_mode(text.trim())
}

#[cfg(target_os = "linux")]
pub fn write_mode(enabled: bool) -> Result<()> {
    fs_err::write(CONSERVATION_MODE_PATH, if enabled { "1\n" } else { "0\n" })
        .map_err(map_linux_node_error)
}

#[cfg(target_os = "linux")]
fn map_linux_node_error(err: std::io::Error) -> Error {
    match err.kind() {
        std::io::ErrorKind::NotFound => Error::LinuxNodeMissing,
        std::io::ErrorKind::PermissionDenied => Error::LinuxPermissionDenied,
        _ => Error::Io(err),
    }
}

#[cfg(target_os = "linux")]
fn parse_mode(value: &str) -> Result<bool> {
    match value {
        "0" => Ok(false),
        "1" => Ok(true),
        other => Err(Error::UnexpectedMode(other.to_owned())),
    }
}

#[cfg(windows)]
pub const WINDOWS_ENERGY_DRV_PATH: &str = r"\\.\EnergyDrv";
#[cfg(windows)]
// Lenovo's EnergyDrv accepts a single in/out buffer for both the GBMD query and
// SBMC state change command. The constants here are observed driver protocol
// values rather than Windows SDK definitions.
const WINDOWS_IOCTL_GBMD_SBMC: u32 = 0x8310_20f8;
#[cfg(windows)]
const WINDOWS_GBMD_CONSERVATION_STATE_BIT: u32 = 5;
#[cfg(windows)]
const WINDOWS_SBMC_CONSERVATION_ON: u8 = 3;
#[cfg(windows)]
const WINDOWS_SBMC_CONSERVATION_OFF: u8 = 5;
#[cfg(windows)]
const WINDOWS_SBMC_QUERY_GBMD: u8 = 0xff;

#[cfg(windows)]
pub fn is_supported_lenovo() -> Result<bool> {
    match windows_backend::EnergyDriver::open(false) {
        Ok(mut driver) => match driver.read_gbmd() {
            Ok(_) | Err(Error::WindowsPermissionDenied) => Ok(true),
            Err(Error::WindowsBackendUnavailable) => Ok(false),
            Err(err) => Err(err),
        },
        Err(Error::WindowsDeviceMissing | Error::WindowsBackendUnavailable) => Ok(false),
        Err(Error::WindowsPermissionDenied) => Ok(true),
        Err(err) => Err(err),
    }
}

#[cfg(windows)]
pub fn read_mode() -> Result<bool> {
    let mut driver = windows_backend::EnergyDriver::open(false)?;
    Ok((driver.read_gbmd()? & (1 << WINDOWS_GBMD_CONSERVATION_STATE_BIT)) != 0)
}

#[cfg(windows)]
pub fn write_mode(enabled: bool) -> Result<()> {
    windows_backend::EnergyDriver::open(true)?.set_conservation_mode(enabled)
}

#[cfg(windows)]
#[allow(unsafe_code)]
mod windows_backend {
    use std::ffi::c_void;
    use std::os::windows::ffi::OsStrExt;

    use windows::Win32::Foundation::{
        CloseHandle, ERROR_ACCESS_DENIED, ERROR_FILE_NOT_FOUND, ERROR_INVALID_FUNCTION,
        ERROR_INVALID_PARAMETER, ERROR_PATH_NOT_FOUND, GENERIC_READ, GENERIC_WRITE, GetLastError,
        HANDLE, INVALID_HANDLE_VALUE,
    };
    use windows::Win32::Storage::FileSystem::{
        CreateFileW, FILE_FLAGS_AND_ATTRIBUTES, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
    };
    use windows::Win32::System::IO::DeviceIoControl;
    use windows::core::PCWSTR;

    use super::{
        Error, Result, WINDOWS_ENERGY_DRV_PATH, WINDOWS_IOCTL_GBMD_SBMC,
        WINDOWS_SBMC_CONSERVATION_OFF, WINDOWS_SBMC_CONSERVATION_ON, WINDOWS_SBMC_QUERY_GBMD,
    };

    pub struct EnergyDriver {
        handle: HANDLE,
    }

    impl EnergyDriver {
        pub fn open(write: bool) -> Result<Self> {
            let path: Vec<u16> = std::ffi::OsStr::new(WINDOWS_ENERGY_DRV_PATH)
                .encode_wide()
                .chain([0])
                .collect();
            let mut access = GENERIC_READ.0;
            if write {
                access |= GENERIC_WRITE.0;
            }
            let handle = match unsafe {
                CreateFileW(
                    PCWSTR(path.as_ptr()),
                    access,
                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                    None,
                    OPEN_EXISTING,
                    FILE_FLAGS_AND_ATTRIBUTES(0),
                    None,
                )
            } {
                Ok(handle) => handle,
                Err(_) => return Err(last_error()),
            };
            if handle == INVALID_HANDLE_VALUE {
                return Err(last_error());
            }
            Ok(Self { handle })
        }

        pub fn read_gbmd(&mut self) -> Result<u32> {
            let mut buffer = [WINDOWS_SBMC_QUERY_GBMD, 0, 0, 0];
            self.ioctl(&mut buffer)?;
            Ok(u32::from_le_bytes(buffer))
        }

        pub fn set_conservation_mode(&mut self, enabled: bool) -> Result<()> {
            let mut buffer = [
                if enabled {
                    WINDOWS_SBMC_CONSERVATION_ON
                } else {
                    WINDOWS_SBMC_CONSERVATION_OFF
                },
                0,
                0,
                0,
            ];
            self.ioctl(&mut buffer)
        }

        fn ioctl(&mut self, buffer: &mut [u8; 4]) -> Result<()> {
            let mut returned = 0_u32;
            // The driver mutates the same 4-byte command buffer in place. For
            // reads it returns the GBMD bitfield; for writes success is enough.
            let result = unsafe {
                DeviceIoControl(
                    self.handle,
                    WINDOWS_IOCTL_GBMD_SBMC,
                    Some(buffer.as_mut_ptr().cast::<c_void>()),
                    buffer.len() as u32,
                    Some(buffer.as_mut_ptr().cast::<c_void>()),
                    buffer.len() as u32,
                    Some(&mut returned),
                    None,
                )
            };
            result.map_err(|_| last_error())
        }
    }

    impl Drop for EnergyDriver {
        fn drop(&mut self) {
            let _ = unsafe { CloseHandle(self.handle) };
        }
    }

    fn last_error() -> Error {
        match unsafe { GetLastError() } {
            ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND => Error::WindowsDeviceMissing,
            ERROR_ACCESS_DENIED => Error::WindowsPermissionDenied,
            ERROR_INVALID_FUNCTION | ERROR_INVALID_PARAMETER => Error::WindowsBackendUnavailable,
            other => Error::Io(std::io::Error::from_raw_os_error(other.0 as i32)),
        }
    }
}

#[cfg(not(any(target_os = "linux", windows)))]
#[allow(clippy::unnecessary_wraps)]
pub const fn is_supported_lenovo() -> Result<bool> {
    Ok(false)
}

#[cfg(not(any(target_os = "linux", windows)))]
pub const fn read_mode() -> Result<bool> {
    Err(Error::UnsupportedOs)
}

#[cfg(not(any(target_os = "linux", windows)))]
pub const fn write_mode(_enabled: bool) -> Result<()> {
    Err(Error::UnsupportedOs)
}

#[cfg(test)]
mod tests {
    #[test]
    #[cfg(target_os = "linux")]
    fn parses_sysfs_mode_values() {
        assert!(!super::parse_mode("0").expect("0 should parse"));
        assert!(super::parse_mode("1").expect("1 should parse"));
        assert!(matches!(
            super::parse_mode("2"),
            Err(crate::Error::UnexpectedMode(_))
        ));
    }
}
