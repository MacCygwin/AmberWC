# Runtime for the settings window: Python + PyGObject + GTK4 + libadwaita.
# The app itself is NOT in the store: ~/.local/share/amber-settings/settings.py
# is run live, so you can edit it and reopen without a rebuild.
#
# configuration.nix:   imports = [ ./hardware-configuration.nix ./amber-settings.nix ];
{ pkgs, ... }:
let
  py = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);

  stub = pkgs.writeText "amber-settings-stub" ''
    #!/usr/bin/env python3
    import os, runpy
    runpy.run_path(os.path.expanduser("~/.local/share/amber-settings/settings.py"), run_name="__main__")
  '';

  amberSettings = pkgs.stdenv.mkDerivation {
    pname = "amber-settings";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.wrapGAppsHook4 pkgs.gobject-introspection py ];
    buildInputs = [ pkgs.gtk4 pkgs.libadwaita pkgs.glib py ];
    installPhase = ''
      install -Dm755 ${stub} $out/bin/amber-settings
    '';
    meta.mainProgram = "amber-settings";
  };
in
{
  environment.systemPackages = [ amberSettings ];
}
