{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixyo"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # Set your time zone.
  time.timeZone = "Asia/Singapore";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_SG.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_SG.UTF-8";
    LC_IDENTIFICATION = "en_SG.UTF-8";
    LC_MEASUREMENT = "en_SG.UTF-8";
    LC_MONETARY = "en_SG.UTF-8";
    LC_NAME = "en_SG.UTF-8";
    LC_NUMERIC = "en_SG.UTF-8";
    LC_PAPER = "en_SG.UTF-8";
    LC_TELEPHONE = "en_SG.UTF-8";
    LC_TIME = "en_SG.UTF-8";
  };

  # Nix itself
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;

  hardware.graphics.enable = true;

  security.pam.services.swaylock = {};
  services.gvfs.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users."testyo" = {
    isNormalUser = true;
    description = "yourname";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    git
    btop
    fastfetch
    ripgrep
    td
    unzip
    zoxide
    fzf

    labwc
    swaybg
    foot
    waybar
    rofi                  # launcher + clipboard picker (Wayland-native since rofi 2.0)
    mako
    grim slurp
    wl-clipboard
    cliphist
    brightnessctl
    (papirus-icon-theme.override { color = "yellow"; })  # amber folders to match the palette
    adw-gtk3              # GTK3/GTK4 base theme, recoloured to the amber palette via gtk.css
    bibata-cursors        # Bibata-Modern-Amber cursor
    font-awesome          # Icons for Waybar modules
    wlogout
    swaylock-effects
    pcmanfm
    libnotify
    swayidle
    wlopm                 # screen off on idle (used by swayidle)
    jq                    # parses makoctl history for the notification list
    (writeShellScriptBin "polkit-agent" "exec ${polkit_gnome}/libexec/polkit-gnome-authentication-agent-1")  # password prompts for admin actions; started from labwc autostart
    poweralertd           # low-battery / plug-in notifications through mako (needs services.upower)
    localsend
    nwg-look              # GTK/Qt theme configurator

    wiremix        # sound mixer (terminal)
    bluetui        # Bluetooth (terminal)
    wdisplays      # monitor layout
    wlsunset       # night light
    fastfetch      # system info

    kdePackages.qt6ct
    kdePackages.qtstyleplugin-kvantum
    libsForQt5.qt5ct
    libsForQt5.qtstyleplugin-kvantum
    adwaita-icon-theme shared-mime-info librsvg
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };  

  security.polkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  fonts.packages = with pkgs; [ nerd-fonts.jetbrains-mono roboto inter noto-fonts-color-emoji ];
  
  programs.firefox.enable = true;

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;          # battery info for poweralertd

  programs.labwc.enable = true;

  # Configure 'ly' display manager with Bendy yellow/black theme
  services.displayManager.ly = {
    enable = true;
    settings = {
      bg = "0x000000";     # Pitch black background matching the wallpaper
      fg = "0xF3B61F";     # Vibrant Bendy amber-yellow text
      border_fg = "0xF3B61F"; # Matching border color
      animation = "none";
      save = true;
      bigclock = true;
    };
  };

  # Theming
  # GTK: adw-gtk3-dark via dconf; the amber colours live in ~/.config/gtk-{3,4}.0/gtk.css
  # Qt:  qt5ct/qt6ct custom amber palette + Kvantum (KvAdaptaDark)
  # Run ./amber-theme-setup.sh once to create the per-user files.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "adw-gtk3-dark";
      icon-theme = "Papirus-Dark";
      cursor-theme = "Bibata-Modern-Amber";
      cursor-size = lib.gvariant.mkInt32 24;
      font-name = "Roboto 10";
      monospace-font-name = "JetBrainsMono Nerd Font 10";
    };
    settings."org/gnome/desktop/wm/preferences".button-layout = ":minimize,maximize,close";
  }];

  environment.variables = {
    QT_QPA_PLATFORMTHEME = "qt5ct";
    QT_QPA_PLATFORMTHEME_QT6 = "qt6ct";
    QT_STYLE_OVERRIDE = "kvantum";
    XCURSOR_THEME = "Bibata-Modern-Amber";
    XCURSOR_SIZE = "24";
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-wlr # Essential for wlroots-based compositors like labwc
      pkgs.xdg-desktop-portal-gtk # Provides GTK dialogs (file pickers, etc.)
    ];
    
    # Set default portal implementation for general requests
    config.common.default = "*";
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  system.stateVersion = "26.05"; # Did you read the comment?

}
