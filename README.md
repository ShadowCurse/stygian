# Stygian
Experimental game engine.

## Build options
### (Default) Platform + Runtime lib (Vulkan backened)
```bash
$ zig build 
or
$ zig build -Dvulkan_render
```

### Platform + Runtime lib (Software backened)
```bash
$ zig build -Dsoftware_render
```

### Single binary (Vulkan backened)
```bash
$ zig build -Dvulkan_render -Dunibuild
```

### Single binary (Software backened)
```bash
$ zig build -Dsoftware_render -Dunibuild
```

### Wasm (Software backened only)
```bash
$ zig build -Dsoftware_render -Dunibuild -Dtarget=wasm32-emscripten --sysroot "emsdk/upstream/emscripten" -Doptimize=ReleaseFast
$ bash wasm.sh
```

## Libraries Used
- [SDL2](https://wiki.libsdl.org/SDL2/FrontPage): creating a window
- [stb](https://github.com/nothings/stb): loading of images and generating font bitmap
- [vma](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator): Vulkan gpu memory management
