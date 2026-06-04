{
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    nvidia.prime = {
      reverseSync.enable = true;
      amdgpuBusId = "PCI:6:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
}
