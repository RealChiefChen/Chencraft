{
  description = "Pinecraft — physics-first logging and mining sandbox";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.${system}.default = pkgs.stdenvNoCC.mkDerivation {
        pname = "pinecraft";
        version = "0.2";
        src = ./.;

        nativeBuildInputs = [ pkgs.godot ];

        buildPhase = ''
          export HOME=$TMPDIR
          # Rebuild class cache then export a PCK
          godot --headless --editor --quit --path . || true
          godot --headless --export-pack "Linux/X11" pinecraft.pck --path . || true
        '';

        installPhase = ''
          mkdir -p $out/share/pinecraft $out/bin

          # Copy game source (Godot runs it directly; no compiled binary needed)
          cp -r . $out/share/pinecraft/
          rm -f $out/share/pinecraft/flake.nix $out/share/pinecraft/flake.lock

          cat > $out/bin/pinecraft <<EOF
          #!/bin/sh
          exec ${pkgs.godot}/bin/godot --path $out/share/pinecraft "\$@"
          EOF
          chmod +x $out/bin/pinecraft
        '';

        meta = {
          description = "Fell it, haul it, mill it, sell it — then build the machines that do it for you";
          homepage = "https://github.com/dell1388/pinecraft";
          license = pkgs.lib.licenses.free;
          platforms = [ "x86_64-linux" ];
        };
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/pinecraft";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.godot ];
        shellHook = ''
          echo "Pinecraft dev shell — run: godot --path ."
        '';
      };
    };
}
