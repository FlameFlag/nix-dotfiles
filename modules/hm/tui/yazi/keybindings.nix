{ myLib, osConfig, ... }:
let
  inherit (osConfig.nixpkgs.hostPlatform) isDarwin;
  inherit (myLib) genKeyBind;

  keymap = [
    (genKeyBind "Open help" [ "~" ] "help")
    (genKeyBind "Undo the last operation" [ "u" ] "undo")
    (genKeyBind "Redo the last operation" [ (if isDarwin then "<D-r>" else "C-r") ] "redo")
    (genKeyBind "Quit Yazi" [ "q" ] "quit")
  ];

  taskKeymap = [
    (genKeyBind "Show the tasks manager" [ "w" ] "tasks:show")
    (genKeyBind "Inspect the task" [ "<Enter>" ] "inspect")
    (genKeyBind "Cancel the task" [ "x" ] "cancel")
  ];

  prependKeymap = [
    (genKeyBind "Maximize Preview" [
      (if isDarwin then "<D-p>" else "<C-p>")
    ] "plugin --sync max-preview")
    (genKeyBind "Diff the selected with the hovered file" [
      (if isDarwin then "<D-d>" else "<C-d>")
    ] "plugin diff")
  ];

  navigationKeymap = [
    (genKeyBind "Move up" [ "<Up>" ] "arrow -1")
    (genKeyBind "Move down" [ "<Down>" ] "arrow 1")

    (genKeyBind "Move up 50%" [ (if isDarwin then "<S-Up>" else "<S-Up>") ] "arrow -50%")
    (genKeyBind "Move down 50%" [ (if isDarwin then "<S-Down>" else "<S-Down>") ] "arrow 50%")

    (genKeyBind "Move to the top" [ (if isDarwin then "<D-Up>" else "<C-Home>") ] "arrow -100%")
    (genKeyBind "Move to the bottom" [ (if isDarwin then "<D-Down>" else "<C-End>") ] "arrow 100%")

    (genKeyBind "Enter directory" [ "<Right>" ] "plugin smart-enter")
    (genKeyBind "Exit directory" [ "<Left>" ] "leave")

    (genKeyBind "Go to a directory interactively" [
      "g"
      "g"
    ] "cd --interactive")
    (genKeyBind "Go to the Config directory" [
      "g"
      "c"
    ] "cd ~/.config")
    (genKeyBind "Go to the Downloads directory" [
      "g"
      "d"
    ] "cd ~/Downloads")
    (genKeyBind "Go to the Home directory" [
      "g"
      "h"
    ] "cd ~/")
    (genKeyBind "Go to the Movies directory" [
      "g"
      "m"
    ] "cd ~/Movies")
    (genKeyBind "Go to the Music directory" [
      "g"
      "u"
    ] "cd ~/Music")
    (genKeyBind "Go to the Pictures directory" [
      "g"
      "p"
    ] "cd ~/Pictures")
  ];

  tabManagementKeymap =
    # Switch to Tab n
    builtins.genList (
      n:
      genKeyBind (builtins.concatStringsSep "" [ "Switch to Tab ${(toString (n + 1))}" ]) [
        "${toString (n + 1)}"
      ] (builtins.concatStringsSep "" [ "tab_switch ${(toString n)}" ])
    ) 9
    ++ [
      (genKeyBind "Close current tab" [ (if isDarwin then "<D-q>" else "<C-q>") ] "close")
      (genKeyBind "Create a new tab using the current path" [ "t" ] "tab_create --current")
      (genKeyBind "Switch to the previous tab" [ "[" ] "tab_switch -1 --relative")
      (genKeyBind "Switch to the next tab" [ "]" ] "tab_switch 1 --relative")
      (genKeyBind "Swap the current tab with the previous tab" [ "{" ] "tab_swap -1")
      (genKeyBind "Swap the current tab with the next tab" [ "}" ] "tab_swap 1")
    ];

  operationsKeymap = [
    (genKeyBind "Open selected file" [ "o" ] "open")
    (genKeyBind "Open selected interactively file" [ "O" ] "open --interactive")
    (genKeyBind "Select all files" [
      (if isDarwin then "<D-a>" else "<C-a>")
    ] "select_all --state=true")

    (genKeyBind "Find next file" [ "/" ] "find --smart")
    (genKeyBind "Find previous file" [ "?" ] "find --previous --smart")
    (genKeyBind "Go to the next found" [ "n" ] "find_arrow")
    (genKeyBind "Go to the previous found" [ "N" ] "find_arrow --previous")

    (genKeyBind "Yank a file (copy)" [ "y" ] "plugin system-clipboard")
    (genKeyBind "Yank a file (cut)" [ "Y" ] "yank --cut")
    (genKeyBind "Cancel the yank status" [ (if isDarwin then "<D-y>" else "<C-y>") ] "unyank")
    (genKeyBind "Copy path to a file" [
      "c"
      "c"
    ] "copy path")
    (genKeyBind "Copy dirname file" [
      "c"
      "d"
    ] "copy dirname")
    (genKeyBind "Copy the filename" [
      "c"
      "f"
    ] "copy filename")
    (genKeyBind "Copy the filename without extension" [
      "c"
      "n"
    ] "copy name_without_ext")
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
    (genKeyBind "Open shell here" [
      (if isDarwin then "<D-s>" else "<C-s>")
    ] "shell \"$SHELL\" --block --confirm")
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
