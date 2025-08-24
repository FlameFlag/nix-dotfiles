_: _: super:
let
  inherit (super)
    concatMapStringsSep
    concatStringsSep
    isInt
    isList
    mapAttrsToList
    optional
    trim
    ;

  /**
    # Type: [String] -> String

    # Example

    ```nix
    formatSchemeList ["ctrl" "shift" "a"]
    # => "(ctrl shift a)"
    ```
  */
  formatSchemeList = keysList: "(${concatStringsSep " " keysList})";

  /**
    # Type: [String] -> String

    # Example

    ```nix
    formatKeyList ["a" "b" "c"]
    # => "a b c"
    ```
  */
  formatKeyList = concatStringsSep " ";

  /**
    # Type: String -> (Int | [a] | String) -> String

    # Example

    ```nix
    mkVariable "tap-time" 200
    # => "(defvar tap-time 200)"

    mkVariable "home-keys" ["a" "s" "d" "f"]
    # => "(defvar home-keys (a s d f))"
    ```
  */
  mkVariable =
    name: value:
    let
      valueStr =
        if isInt value then
          toString value
        else if isList value then
          formatSchemeList value
        else
          value;
    in
    "(defvar ${name} ${valueStr})";

  /**
    # Type: String -> String -> String

    # Example

    ```nix
    mkAlias "ctrl-a" "(tap-hold 200 200 a lctrl)"
    # => "ctrl-a (tap-hold 200 200 a lctrl)"
    ```
  */
  mkAlias = name: definition: "${name} ${definition}";

  /**
    # Type: String -> String -> String -> Int -> Int -> String

    # Example

    ```nix
    mkTapHold "ctrl-a" "a" "lctrl" 200 200
    # => "ctrl-a (tap-hold 200 200 a lctrl)"
    ```
  */
  mkTapHold =
    aliasName: tapKey: holdAction: timeoutHold: timeoutTap:
    mkAlias aliasName "(tap-hold ${toString timeoutHold} ${toString timeoutTap} ${tapKey} ${holdAction})";

  /**
    # Type:  String -> String -> String -> Int -> Int -> [String] -> String

    # Example

    ```nix
    mkTapHoldReleaseKeys "ctrl-a" "a" "lctrl" 200 200 ["j" "k" "l"]
    # => "ctrl-a (tap-hold-release-keys 200 200 a lctrl (j k l))"
    ```
  */
  mkTapHoldReleaseKeys =
    aliasName: tapKey: holdAction: timeoutHold: timeoutTap: releaseKeysList:
    mkAlias aliasName "(tap-hold-release-keys ${toString timeoutHold} ${toString timeoutTap} ${tapKey} ${holdAction} ${formatSchemeList releaseKeysList})";

  /**
    # Type: String -> String -> String -> Int -> Int -> String

    # Example

    ```nix
    mkLayerSwitch "nav-spc" "spc" "navigation" 200 200
    # => "nav-spc (tap-hold 200 200 spc (layer-switch navigation))"
    ```
  */
  mkLayerSwitch =
    aliasName: tapKey: layerName: timeoutHold: timeoutTap:
    mkTapHold aliasName tapKey "(layer-switch ${layerName})" timeoutHold timeoutTap;

  /**
    # Type: String -> String -> String -> Int -> Int -> String

    # Example

    ```nix
    mkLayerWhileHeld "sym-spc" "spc" "symbols" 200 200
    # => "sym-spc (tap-hold 200 200 spc (layer-while-held symbols))"
    ```
  */
  mkLayerWhileHeld =
    aliasName: tapKey: layerName: timeoutHold: timeoutTap:
    mkTapHold aliasName tapKey "(layer-while-held ${layerName})" timeoutHold timeoutTap;

  /**
    # Type: String -> String -> [String] -> Int -> Int -> String

    # Example

    ```nix
    mkMultiMod "ctrl-shift-a" "a" ["lctrl" "lshift"] 200 200
    # => "ctrl-shift-a (tap-hold 200 200 a (multi lctrl lshift))"
    ```
  */
  mkMultiMod =
    aliasName: tapKey: modifiers: timeoutHold: timeoutTap:
    mkTapHold aliasName tapKey "(multi ${concatStringsSep " " modifiers})" timeoutHold timeoutTap;

  /**
    # Type: String -> [String] -> String

    # Example

    ```nix
    mkLayer "qwerty" [
      "q" "w" "e" "r" "t" "y" "u" "i" "o" "p"
      "a" "s" "d" "f" "g" "h" "j" "k" "l" ";"
      "z" "x" "c" "v" "b" "n" "m" "," "." "/"
    ]
    # => '''
    # (deflayer qwerty
    #   q w e r t y u i o p
    #   a s d f g h j k l ;
    #   z x c v b n m , . /
    # )
    # '''
    ```
  */
  mkLayer = name: keyMappings: ''
    (deflayer ${name}
      ${formatKeyList keyMappings}
    )
  '';

  /**
    # Type: [String] -> String -> String -> String -> [String] -> String

    # Example

    ```nix
    mkChord ["j" "k"] "esc" "chord-timeout" "first-release" []
    # => "(j k) esc chord-timeout first-release ()"
    ```
  */
  mkChord =
    keys: action: timeoutVar: behavior: disabledLayers:
    "${formatSchemeList keys} ${action} ${timeoutVar} ${behavior} ${formatSchemeList disabledLayers}";

  /**
    # Type: [a] -> (a -> b) -> [b]
  */
  mapKeys = keyList: mappingFn: super.map mappingFn keyList;

  /**
    # Type: String -> (String | AttrSet) -> String

    # Example

    ```nix
    mapKey "a" { alias = "ctrl-a"; }
    # => "@ctrl-a"

    mapKey "b" "custom-b"
    # => "custom-b"
    ```
  */
  mapKey =
    key: mapping:
    if builtins.isString mapping then
      mapping
    else if builtins.isAttrs mapping then
      if mapping ? alias then
        "@${mapping.alias}"
      else if mapping ? key then
        mapping.key
      else
        key
    else
      key;

  /**
    # Type: AttrSet String Int -> String

    # Example

    ```nix
    mkLocalKeys {
      "custom-key" = 125;
      "special-fn" = 126;
    }
    # => '''
    # (deflocalkeys-linux
    #   custom-key 125
    #   special-fn 126
    # )
    # '''
    ```
  */
  mkLocalKeys = localKeyDefs: ''
    (deflocalkeys-linux
      ${concatStringsSep "\n  " (
        mapAttrsToList (name: keycode: "${name} ${toString keycode}") localKeyDefs
      )}
    )
  '';

  /**
    # Type

    ```
    {
      variables :: AttrSet String a,
      aliases :: [String],
      layers :: AttrSet String [String],
      chords :: [String],
      sourceKeys :: [String],
      localKeys :: AttrSet String Int,
      extraDefCfg :: [String]
    } -> String
    ```

    # Example

    ```nix
    mkConfig {
      variables = { "tap-time" = 200; };
      aliases = [
        (mkTapHold "ctrl-a" "a" "lctrl" 200 200)
      ];
      layers = {
        "qwerty" = ["q" "w" "e" ... ];
        "navigation" = ["left" "down" "up" "right" ... ];
      };
      chords = [];
      sourceKeys = ["q" "w" "e" ... ];
      localKeys = {};
      extraDefCfg = [];
    }
    ```
  */
  mkConfig =
    {
      variables ? { },
      aliases ? [ ],
      layers ? { },
      chords ? [ ],
      sourceKeys,
      localKeys ? { },
      extraDefCfg ? [ ],
    }:
    let
      varsSection = super.mapAttrsToList mkVariable variables;
      localKeysSection = if localKeys == { } then "" else mkLocalKeys localKeys;
      aliasesSection =
        if aliases == [ ] then
          ""
        else
          ''
            (defalias
              ${concatMapStringsSep "\n  " trim aliases}
            )
          '';
      layersSection = mapAttrsToList mkLayer layers;
      chordsSection =
        if chords == [ ] then
          ""
        else
          ''
            (defchordsv2
              ${concatStringsSep "\n  " chords}
            )
          '';
    in
    concatStringsSep "\n" (
      builtins.concatLists [
        [ ";; Generated Kanata config by Nix" ]
        (optional (localKeysSection != "") localKeysSection)
        [
          ''
            (defsrc
              ${formatKeyList sourceKeys}
            )
          ''
        ]
        varsSection
        (optional (chordsSection != "") chordsSection)
        layersSection
        (optional (aliasesSection != "") aliasesSection)
      ]
    );

  /**
    # Type

    ```
    {
      keys :: [String],
      mods :: [String],
      behavior :: String,
      tapTimeout :: Int,
      holdTimeout :: Int,
      releaseKeys :: [String]
    } -> AttrSet
    ```

    # Example

    ```nix
    mkHomeRowModConfig {
      keys = ["a" "s" "d" "f"];
      mods = ["lgui" "lalt" "lctrl" "lshift"];
      behavior = "tap-hold";
      tapTimeout = 220;
      holdTimeout = 240;
      releaseKeys = [];
    }
    # => {
    #   "a" = { mod = "lgui"; behavior = "tap-hold"; ... };
    #   "s" = { mod = "lalt"; behavior = "tap-hold"; ... };
    #   # ... etc
    # }
    ```
  */
  mkHomeRowModConfig =
    {
      keys,
      mods,
      behavior ? "tap-hold",
      tapTimeout ? 220,
      holdTimeout ? 240,
      releaseKeys ? [ ],
    }:
    let
      keyModPairs = super.zipLists keys mods;
    in
    super.foldl' super.recursiveUpdate { } (
      super.map (
        { fst, snd }:
        {
          ${fst} = {
            mod = snd;
            timeoutTap = tapTimeout;
            timeoutHold = holdTimeout;
            inherit
              behavior
              releaseKeys
              ;
          };
        }
      ) keyModPairs
    );

  /**
    # Type

    ```
    {
      name :: String,
      keys :: [String],
      positions :: [Int],
      fillWith :: String
    } -> AttrSet String [String]
    ```

    # Example

    ```nix
    mkNavigationLayer {
      name = "nav";
      keys = ["left" "down" "up" "right"];
      positions = [7 8 9 10];  # hjkl positions
      fillWith = "_";
    }
    # => {
    #   "nav" = ["_" "_" "_" "_" "_" "_" "_" "left" "down" "up" "right" "_" "_" "_" "_" "_"];
    # }
    ```

    # Notes

    This function assumes a 16-key layout but can be extended for other layouts.
    The positions correspond to the physical key positions in your layout.
  */
  mkNavigationLayer =
    {
      name ? "nav",
      keys ? [
        "left"
        "down"
        "up"
        "right"
      ],
      positions ? [
        7
        8
        9
        10
      ], # hjkl positions in common layouts
      fillWith ? "_",
    }:
    let
      totalKeys = 16; # Common layout size
      navMap = super.listToAttrs (
        super.zipListsWith (pos: key: {
          name = toString pos;
          value = key;
        }) positions keys
      );
    in
    {
      ${name} = super.genList (i: navMap.${toString i} or fillWith) totalKeys;
    };
in
{
  inherit
    formatKeyList
    formatSchemeList
    mapKey
    mapKeys
    mkAlias
    mkChord
    mkConfig
    mkHomeRowModConfig
    mkLayer
    mkLayerSwitch
    mkLayerWhileHeld
    mkLocalKeys
    mkMultiMod
    mkNavigationLayer
    mkTapHold
    mkTapHoldReleaseKeys
    mkVariable
    ;
}
