_: {
  system = {
    # Global macOS System Settings
    defaults = {
      LaunchServices.LSQuarantine = false; # Disable Quarantine for Downloaded Applications
      SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;
      NSGlobalDomain = {
        # Apple menu > System Preferences > Keyboard
        KeyRepeat = 2;

        AppleMetricUnits = 1; # Use Metric

        AppleInterfaceStyleSwitchesAutomatically = true; # Auto Switch Light-Dark Mode

        NSAutomaticWindowAnimationsEnabled = false; # Disable opening and closing animation

        NSDocumentSaveNewDocumentsToCloud = false; # Disable auto save text files to iCloud

        NSAutomaticCapitalizationEnabled = false; # Disable auto capitalization
        NSAutomaticSpellingCorrectionEnabled = false; # Disable spell checker
        NSAutomaticPeriodSubstitutionEnabled = false; # Disable adding . after pressing space twice

        NSAutomaticDashSubstitutionEnabled = false; # Disable "smart" dash substitution
        NSAutomaticQuoteSubstitutionEnabled = false; # No "smart" quote substitution
      };
      menuExtraClock = {
        Show24Hour = true; # Use 24 hour clock
        ShowSeconds = true; # Show Seconds
        ShowDate = 2; # Don't show date (Use Itsycal)
      };
      finder = {
        AppleShowAllFiles = false; # Show all files
        AppleShowAllExtensions = true; # Show all file extensions
        FXEnableExtensionChangeWarning = false; # Disable Warning for changing extension
        FXPreferredViewStyle = "icnv"; # Change the default finder view. “icnv” = Icon view
        QuitMenuItem = true; # Allow qutting Finder
        ShowPathbar = true; # Show full path at bottom
      };
      dock = {
        autohide = true;
        magnification = false;
        orientation = "bottom";
        show-recents = false; # Show Recently Open
        showhidden = true;
        tilesize = 65; # Size of Dock Icons

        # Disable all Corners, 1 = Disabled
        # Top Left
        wvous-tl-corner = 1;
        # Top Right
        wvous-tr-corner = 1;
        # Bottom Left
        wvous-bl-corner = 1;
        # Bottom Right
        wvous-br-corner = 1;
      };
    };

    # Used for backwards compatibility, please read the changelog before changing.
    # $ darwin-rebuild changelog
    stateVersion = 6;
  };
}
