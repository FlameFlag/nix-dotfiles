{ myLib, osConfig, ... }:
let
  inherit (myLib) genKeyBind genModBind genGoBind;
  inherit (osConfig.nixpkgs.hostPlatform) isDarwin;

  keymap = [
    (genKeyBind "Open help" [ "~" ] "help")
    (genKeyBind "Undo the last operation" [ "u" ] "undo")
    (genModBind "Redo the last operation" "r" "redo")
    (genKeyBind "Quit Yazi" [ "q" ] "quit")
  ];

  taskKeymap = [
    (genKeyBind "Show the tasks manager" [ "w" ] "tasks:show")
    (genKeyBind "Inspect the task" [ "<Enter>" ] "inspect")
    (genKeyBind "Cancel the task" [ "x" ] "cancel")
  ];

  prependKeymap = [
    (genModBind "Maximize Preview" "p" "plugin --sync max-preview")
    (genModBind "Diff the selected with the hovered file" "d" "plugin diff")
  ];

  navigationKeymap =
    let
      destinations = {
        c = {
          name = "Config";
          path = "~/.config";
        };
        d = {
          name = "Downloads";
          path = "~/Downloads";
        };
        h = {
          name = "Home";
          path = "~/";
        };
        m = {
          name = "Movies";
          path = "~/Movies";
        };
        u = {
          name = "Music";
          path = "~/Music";
        };
        p = {
          name = "Pictures";
          path = "~/Pictures";
        };
      };
    in
    [
      (genKeyBind "Move up" [ "<Up>" ] "arrow -1")
      (genKeyBind "Move down" [ "<Down>" ] "arrow 1")
      (genKeyBind "Move up 50%" [ "<S-Up>" ] "arrow -50%")
      (genKeyBind "Move down 50%" [ "<S-Down>" ] "arrow 50%")
      (genKeyBind "Move to the top" [ (if isDarwin then "<D-Up>" else "<C-Home>") ] "arrow -100%")
      (genKeyBind "Move to the bottom" [ (if isDarwin then "<D-Down>" else "<C-End>") ] "arrow 100%")
      (genKeyBind "Enter directory" [ "<Right>" ] "plugin smart-enter")
      (genKeyBind "Exit directory" [ "<Left>" ] "leave")
      (genKeyBind "Go to a directory interactively" [ "g" "g" ] "cd --interactive")
    ]
    ++ (builtins.attrValues (
      builtins.mapAttrs (key: value: genGoBind key value.name value.path) destinations
    ));

  tabManagementKeymap =
    # Switch to Tab n
    builtins.genList (
      n: genKeyBind "Switch to Tab ${toString (n + 1)}" [ (toString (n + 1)) ] "tab_switch ${toString n}"
    ) 9
    ++ [
      (genModBind "Close current tab" "q" "close")
      (genKeyBind "Create a new tab using the current path" [ "t" ] "tab_create --current")
      (genKeyBind "Switch to the previous tab" [ "[" ] "tab_switch -1 --relative")
      (genKeyBind "Switch to the next tab" [ "]" ] "tab_switch 1 --relative")
      (genKeyBind "Swap the current tab with the previous tab" [ "{" ] "tab_swap -1")
      (genKeyBind "Swap the current tab with the next tab" [ "}" ] "tab_swap 1")
    ];

  operationsKeymap = [
    (genKeyBind "Open selected file" [ "o" ] "open")
    (genKeyBind "Open selected interactively file" [ "O" ] "open --interactive")
    (genModBind "Select all files" "a" "select_all --state=true")

    (genKeyBind "Find next file" [ "/" ] "find --smart")
    (genKeyBind "Find previous file" [ "?" ] "find --previous --smart")
    (genKeyBind "Go to the next found" [ "n" ] "find_arrow")
    (genKeyBind "Go to the previous found" [ "N" ] "find_arrow --previous")

    (genKeyBind "Yank a file (copy)" [ "y" ] "plugin system-clipboard")
    (genKeyBind "Yank a file (cut)" [ "Y" ] "yank --cut")
    (genModBind "Cancel the yank status" "y" "unyank")
    (genKeyBind "Copy path to a file" [ "c" "c" ] "copy path")
    (genKeyBind "Copy dirname file" [ "c" "d" ] "copy dirname")
    (genKeyBind "Copy the filename" [ "c" "f" ] "copy filename")
    (genKeyBind "Copy the filename without extension" [ "c" "n" ] "copy name_without_ext")
    (genKeyBind "Paste a file" [ "p" ] "plugin smart-paste")
    (genKeyBind "Paste a file (force)" [ "P" ] "plugin smart-paste --force")

    (genKeyBind "Run a shell command" [ ":" ] "shell --interactive")
    (genKeyBind "Create a file (ends with / for directories)" [ "a" ] "create")
    (genKeyBind "Delete a file" [ "<S-D>" ] "remove")
    (genKeyBind "Rename selected file(s)" [ "r" ] "rename --cursor=before_ext")
    (genKeyBind "Search files by content using ripgrep" [ "s" ] "search rg")
  ];

  modeSwitchingKeymap = [
    (genKeyBind "Enter Visual Mode (Select)" [ "v" ] "visual_mode")
    (genKeyBind "Exit Visual Mode (Unset)" [ "V" ] "visual_mode")
    (genKeyBind "Go back to normal mode or cancel input" [ "<Esc>" ] "escape")
    (genModBind "Open shell here" "s" "shell \"$SHELL\" --block --confirm")
  ];
in
{
  programs.yazi.keymap = {
    mgr.prepend_keymap = prependKeymap;
    mgr.keymap =
      keymap
      ++ taskKeymap
      ++ navigationKeymap
      ++ tabManagementKeymap
      ++ operationsKeymap
      ++ modeSwitchingKeymap;
  };
}
