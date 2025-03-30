# Stygian
Experimental game engine.

## Build

### Platform + Runtime lib
```bash
$ zig build 
```

### Single binary
```bash
$ zig build -Dunibuild
```

### Compile specific example
```bash
$ zig build -Dcompile_shaders -Druntime_src_path=./examples/runtime_radiance_cascades.zig
```

## Libraries Used
- [SDL3](https://wiki.libsdl.org/SDL3/FrontPage): creating a window
- [stb](https://github.com/nothings/stb): loading of images and generating font bitmap
- [vma](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator): Vulkan gpu memory management
