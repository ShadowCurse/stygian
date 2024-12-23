{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  X11_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [
    pkgs.xorg.libX11
  ]}";
  # needed for X.h file
  XORGPROTO_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [
    pkgs.xorg.xorgproto
  ]}";
  SDL2_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.SDL2]}";
  VULKAN_INCLUDE_PATH = "${pkgs.lib.makeIncludePath [pkgs.vulkan-headers]}";
  VULKAN_SDK = "${pkgs.vulkan-headers}";
  VK_LAYER_PATH = "${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d";
  LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [pkgs.vulkan-loader]}";
  EM_CACHE="/home/antaraz/.emscripten_cache";

  buildInputs = with pkgs; [
    SDL2
    vulkan-tools
    vulkan-loader
    vulkan-headers
    vulkan-validation-layers
    pkg-config
    shaderc

    emscripten
  ];
}
