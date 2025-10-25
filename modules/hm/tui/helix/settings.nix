_:
let
  repeatedBinds = {
    "{" = "page_cursor_half_up";
    "}" = "page_cursor_half_down";
    G = "goto_file_end";
    g = {
      g = "goto_file_start";
      q = ":reflow";
    };
    Z = {
      Z = ":write-quit";
      Q = ":quit!";
    };
  };
in
{
  programs.helix.settings = {
    theme.light = "catppuccin_light";
    theme.dark = "catppuccin_frappe";

    editor = {
      # Core
      auto-format = true;
      auto-save = false;
      idle-timeout = 50;

      # Visual
      color-modes = true;
      cursorline = true;
      cursor-shape = {
        insert = "bar";
        normal = "block";
        select = "underline";
      };
      gutters = [
        "diagnostics"
        "line-numbers"
        "spacer"
        "diff"
      ];
      indent-guides.render = true;
      line-number = "relative";
      rulers = [
        72
        80
        100
        120
      ];
      statusline.center = [ "position-percentage" ];
      true-color = true;
      whitespace.characters = {
        nbsp = "⍽";
        newline = "⏎";
        space = "·";
        tab = "→";
        tabpad = "·";
        trail = "•";
      };

      # LSP and Completion
      completion-replace = true;
      completion-trigger-len = 1;
      lsp = {
        display-messages = true;
        display-inlay-hints = true;
      };

      # File and Buffer
      bufferline = "always";
      file-picker = {
        git-global = true;
        git-ignore = true;
        hidden = false;
      };
      soft-wrap.enable = true;

      # Search
      search = {
        smart-case = true;
        wrap-around = true;
      };

      mouse = true;
    };

    keys = {
      normal = repeatedBinds // {
        space.space = "file_picker";
        esc = [
          "collapse_selection"
          "keep_primary_selection"
        ];
      };
      select = repeatedBinds // { };
    };
  };
}
