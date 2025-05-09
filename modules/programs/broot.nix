{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    literalExpression
    mkIf
    mkOption
    mkRenamedOptionModule
    types
    ;

  cfg = config.programs.broot;

  jsonFormat = pkgs.formats.json { };

  settingsModule = {
    freeformType = jsonFormat.type;

    options = {
      modal = lib.mkEnableOption "modal (vim) mode";

      verbs = mkOption {
        type =
          with types;
          listOf (
            attrsOf (oneOf [
              bool
              str
              (listOf str)
            ])
          );
        default = [ ];
        example = literalExpression ''
          [
            { invocation = "p"; execution = ":parent"; }
            { invocation = "edit"; shortcut = "e"; execution = "$EDITOR {file}" ; }
            { invocation = "create {subpath}"; execution = "$EDITOR {directory}/{subpath}"; }
            { invocation = "view"; execution = "less {file}"; }
            {
              invocation = "blop {name}\\.{type}";
              execution = "mkdir {parent}/{type} && ''${pkgs.neovim}/bin/nvim {parent}/{type}/{name}.{type}";
              from_shell = true;
            }
          ]
        '';
        description = ''
          Define new verbs. For more information, see
          [Verb Definition Attributes](https://dystroy.org/broot/documentation/configuration/#verb-definition-attributes)
          in the broot documentation.

          The possible attributes are:

          `invocation` (optional)
          : how the verb is called by the user, with placeholders for arguments

          `execution` (mandatory)
          : how the verb is executed

          `key` (optional)
          : a keyboard key triggering execution

          `keys` (optional)
          : multiple keyboard keys each triggering execution

          `shortcut` (optional)
          : an alternate way to call the verb (without
            the arguments part)

          `leave_broot` (optional)
          : whether to quit broot on execution
            (default: `true`)

          `from_shell` (optional)
          : whether the verb must be executed from the
            parent shell (default: `false`)
        '';
      };

      skin = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = literalExpression ''
          {
            status_normal_fg = "grayscale(18)";
            status_normal_bg = "grayscale(3)";
            status_error_fg = "red";
            status_error_bg = "yellow";
            tree_fg = "red";
            selected_line_bg = "grayscale(7)";
            permissions_fg = "grayscale(12)";
            size_bar_full_bg = "red";
            size_bar_void_bg = "black";
            directory_fg = "lightyellow";
            input_fg = "cyan";
            flag_value_fg = "lightyellow";
            table_border_fg = "red";
            code_fg = "lightyellow";
          }
        '';
        description = ''
          Color configuration.

          Complete list of keys (expected to change before the v1 of broot):

          * `char_match`
          * `code`
          * `directory`
          * `exe`
          * `file`
          * `file_error`
          * `flag_label`
          * `flag_value`
          * `input`
          * `link`
          * `permissions`
          * `selected_line`
          * `size_bar_full`
          * `size_bar_void`
          * `size_text`
          * `spinner`
          * `status_error`
          * `status_normal`
          * `table_border`
          * `tree`
          * `unlisted`

          Add `_fg` for a foreground color and
          `_bg` for a background color.
        '';
      };
    };
  };

  shellInit =
    shell:
    # Using mkAfter to make it more likely to appear after other
    # manipulations of the prompt.
    lib.mkAfter ''
      source ${
        pkgs.runCommand "br.${shell}" {
          nativeBuildInputs = [ cfg.package ];
        } "broot --print-shell-function ${shell} > $out"
      }
    '';
in
{
  meta.maintainers = [
    lib.hm.maintainers.aheaume
    lib.maintainers.dermetfan
  ];

  imports = [
    (mkRenamedOptionModule
      [ "programs" "broot" "modal" ]
      [
        "programs"
        "broot"
        "settings"
        "modal"
      ]
    )
    (mkRenamedOptionModule
      [ "programs" "broot" "verbs" ]
      [
        "programs"
        "broot"
        "settings"
        "verbs"
      ]
    )
    (mkRenamedOptionModule
      [ "programs" "broot" "skin" ]
      [
        "programs"
        "broot"
        "settings"
        "skin"
      ]
    )
  ];

  options.programs.broot = {
    enable = lib.mkEnableOption "Broot, a better way to navigate directories";

    enableBashIntegration = lib.hm.shell.mkBashIntegrationOption { inherit config; };

    enableFishIntegration = lib.hm.shell.mkFishIntegrationOption { inherit config; };

    enableNushellIntegration = lib.hm.shell.mkNushellIntegrationOption { inherit config; };

    enableZshIntegration = lib.hm.shell.mkZshIntegrationOption { inherit config; };

    package = lib.mkPackageOption pkgs "broot" { };

    settings = mkOption {
      type = types.submodule settingsModule;
      default = { };
      description = "Verbatim config entries";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile.broot = {
      recursive = true;
      source = pkgs.symlinkJoin {
        name = "xdg.configFile.broot";
        paths = [
          # Copy all files under /resources/default-conf
          "${cfg.package.src}/resources/default-conf"

          # Dummy file to prevent broot from trying to reinstall itself
          (pkgs.writeTextDir "launcher/installed-v1" "")
        ];
        postBuild = ''
          rm $out/conf.hjson
          ${lib.getExe pkgs.jq} --slurp add > $out/conf.hjson \
            <(${lib.getExe pkgs.hjson-go} -c ${cfg.package.src}/resources/default-conf/conf.hjson) \
            ${jsonFormat.generate "broot-config.json" cfg.settings}
        '';
      };
    };

    programs = {
      bash.initExtra = mkIf cfg.enableBashIntegration (shellInit "bash");

      zsh.initContent = mkIf cfg.enableZshIntegration (shellInit "zsh");

      fish.shellInit = mkIf cfg.enableFishIntegration (shellInit "fish");

      nushell.extraConfig = mkIf cfg.enableNushellIntegration (shellInit "nushell");
    };
  };
}
