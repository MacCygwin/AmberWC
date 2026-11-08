# Home Manager module: links everything under home/ into $HOME.
# The links point at the live checkout (~/dotfiles/home), so edits apply at once with
# no rebuild. Rebuild only when you add a NEW top-level file or folder under home/.
{ config, lib, ... }:
let
  live = "${config.home.homeDirectory}/dotfiles/home";   # the checkout you edit
  repo = ../home;                                        # same files, only used to list names

  link = rel: skip:
    lib.mapAttrs'
      (name: _: lib.nameValuePair "${rel}/${name}" {
        source = config.lib.file.mkOutOfStoreSymlink "${live}/${rel}/${name}";
      })
      (lib.filterAttrs (n: _: !(builtins.elem n skip)) (builtins.readDir (repo + "/${rel}")));
in
{
  home.stateVersion = "26.05";

  home.file =
    link ".config" [ "waybar" ]
    // link ".config/waybar" [ "config.jsonc" "style.css" ]
    // link ".local/bin" [ ]
    // link ".local/share" [ ]
    // link "Pictures" [ ];

  # settings-hub, pp-cycle and friends are called by bare name
  home.sessionPath = [ "$HOME/.local/bin" ];

  # waybar_switch.sh repoints these two links at runtime, so they are not managed above.
  home.activation.waybarStyle = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    d="$HOME/.config/waybar"
    for f in config.jsonc style.css; do
      if [ ! -e "$d/$f" ] && [ ! -L "$d/$f" ]; then
        run ln -s "$d/default/$f" "$d/$f"
      fi
    done
  '';
}
