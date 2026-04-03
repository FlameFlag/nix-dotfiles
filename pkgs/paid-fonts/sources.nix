{
  rev = "0abd75f1ccb4aee0eb7ea9e9d479d2d6a16fc86d";

  fonts = {
    tx-02 = {
      pname = "tx-02-nerd-font";
      version = "2.002";
      path = "TX-02";
      format = "ttf";
      patchNerd = true;
      description = "TX-02 font patched with Nerd Font glyphs";
    };

    sohne-mono = {
      pname = "sohne-mono-nerd-font";
      version = "1.107";
      path = "Sohne/OTF";
      glob = "SohneMono-*";
      format = "otf";
      patchNerd = true;
      description = "Söhne Mono patched with Nerd Font glyphs";
    };

    sohne = {
      pname = "sohne-font";
      version = "1.107";
      path = "Sohne/OTF";
      glob = "Sohne-*";
      format = "otf";
      patchNerd = false;
      description = "Söhne font family";
    };

    sohne-breit = {
      pname = "sohne-breit-font";
      version = "1.107";
      path = "Sohne/OTF";
      glob = "SohneBreit-*";
      format = "otf";
      patchNerd = false;
      description = "Söhne Breit font family";
    };

    sohne-schmal = {
      pname = "sohne-schmal-font";
      version = "1.107";
      path = "Sohne/OTF";
      glob = "SohneSchmal-*";
      format = "otf";
      patchNerd = false;
      description = "Söhne Schmal font family";
    };
  };
}
