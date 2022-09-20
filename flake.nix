{
  description = "A WiiU Emulator";
  
  inputs = {
    flake_utils.url = "github:numtide/flake-utils";
    cemu_src = {
      url = "github:cemu-project/Cemu/main";
      flake = false;
    };
    # use same version that cemu has as submodule
    cubeb_src = {
      url = "github:mozilla/cubeb/dc511c6b3597b6384d28949285b9289e009830ea";
      flake = false;
    };
    # same version as in submodules
    zarchive_src = {
      url = "github:Exzap/ZArchive/48914a07df3c213333c580bb5e5bb3393442ca5b";
      flake = false;
    };
    # latest release
    imgui_src = {
      url = "github:ocornut/imgui/v1.88";
      flake = false;
    };
    # latest release
    glslang_src = {
      url = "github:KhronosGroup/glslang/11.11.0";
      flake = false;
    };
    # for imgui CMake files
    vcpkg_src = {
      url = "github:microsoft/vcpkg/2022.08.15";
      flake = false;
    };
    # cemu wants 9.1.0, nixpkgs only has 9.0.0
    fmt_src = {
      url = "github:fmtlib/fmt/9.1.0";
      flake = false;
    };
    # used by cubeb as submodule
    sanitizers_src = {
      url = "github:arsenm/sanitizers-cmake/aab6948fa863bc1cbe5d0850bc46b9ef02ed4c1a";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake_utils, cemu_src, cubeb_src, zarchive_src, imgui_src, glslang_src, vcpkg_src, fmt_src, sanitizers_src }:
    flake_utils.lib.eachDefaultSystem
      (system: 
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          # dependency of cemu
          packages.cubeb = pkgs.stdenv.mkDerivation {
            name = "cubeb";
            version = "0.1.0";
            
            src = cubeb_src;
            
            postPatch = ''
              rm -r cmake/sanitizers-cmake
              cp -r ${sanitizers_src} cmake/sanitizers-cmake
              chmod -R 755 cmake/sanitizers-cmake
            '';

            nativeBuildInputs = with pkgs; [ cmake ];

            buildInputs = with pkgs; [ libpulseaudio ];

            # for now
            # googletest is a submodule which is broken with flakes
            cmakeFlags = [
              "-DBUILD_TESTS=OFF"
            ];
          };
          
          packages.zarchive = pkgs.stdenv.mkDerivation {
            name = "zarchive";
            version = "0.1.0";
            
            src = zarchive_src;
            
            nativeBuildInputs = with pkgs; [
              cmake
              pkgconfig
            ];
            
            buildInputs = with pkgs; [
              zstd
            ];
          };
          
          # custom imgui that works with cmake https://github.com/NixOS/nixpkgs/issues/188187#issuecomment-1236256398
          packages.imgui = pkgs.stdenv.mkDerivation {
            name = "imgui";
            version = "0.1.0";
            
            src = imgui_src;
            
            postPatch = ''
              cp ${vcpkg_src}/ports/imgui/{CMakeLists.txt,imgui-config.cmake.in} .
            '';
            
            nativeBuildInputs = with pkgs; [
              cmake
            ];
          };
          
          # custom glslang because for some reason the one from nixpkgs did not work
          packages.glslang = pkgs.stdenv.mkDerivation {
            name = "glslang";
            version = "0.1.0";
            src = glslang_src;
            
            nativeBuildInputs = with pkgs; [
              cmake
              python3
            ];
          };
          
          # updated version of wxwidgets. Cemu wants 3.2.0, nixpkgs only has 3.1.0
          # tried using the -gtk3 variant, but it did not work
          packages.wxGTK32 = pkgs.wxGTK31-gtk3.overrideAttrs(old: rec{
            version = "3.2.0";
            
            src = pkgs.fetchFromGitHub {
              owner = "wxWidgets";
              repo = "wxWidgets";
              rev = "v3.2.0";
              hash = "sha256-8rOnIyNADQsZBmiofrxRc52WWNFH5u39gH/1FKKF4ZQ=";
              fetchSubmodules = true;
            };
          });
          
          # updated version of fmt
          packages.fmt = pkgs.stdenv.mkDerivation {
            name = "fmt";
            version = "0.1.0";
            
            src = fmt_src;
            
            nativeBuildInputs = with pkgs; [
              cmake
            ];
          };
          
          packages.cemu = pkgs.stdenv.mkDerivation rec{
            name = "Cemu Emulator";
            version = "0.1.0";
        
            src = cemu_src;

            xdgPatch = pkgs.fetchurl {
              url = "https://github.com/cemu-project/Cemu/pull/130.diff";
              sha256 = "045xhwaa4p9n6h75965k79kiyr9a2yv1iv07yra9vi6fpf3c436l";
            };

            nativeBuildInputs = with pkgs; [
              cmake
              ninja
              imgui
              glslang
              pkgconfig
              nasm
              makeWrapper
              wrapGAppsHook
            ];
            
            buildInputs = with pkgs; [
              SDL2
              pugixml
              imgui
              rapidjson
              boost
              libzip
              zlib
              zstd
              curl
              openssl
              glm
              libpng
              vulkan-headers
              vulkan-loader
              xorg.libXrender

              # custom packages
              self.packages.${system}.wxGTK32
              self.packages.${system}.cubeb
              self.packages.${system}.zarchive
              self.packages.${system}.imgui
              self.packages.${system}.glslang
              self.packages.${system}.fmt
            ];

            patches = [ xdgPatch ];

            postPatch = ''
              sed -i 's:include_directories(\"dependencies/Vulkan-Headers/include\"):find_package(Vulkan REQUIRED):g' CMakeLists.txt
            '';

            cmakeFlags = [
              "-DENABLE_VCPKG=OFF"
            ];

            postInstall = ''
              mkdir -p $out/bin
              cp ../bin/Cemu_release $out/bin/
            '';

            postFixup = ''
              wrapProgram $out/bin/Cemu_release \
                --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.libpulseaudio pkgs.vulkan-loader ]}
            '';
          };

          defaultPackage = self.packages.${system}.cemu;
        }
      );
}
