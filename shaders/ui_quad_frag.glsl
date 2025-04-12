#version 450

#extension GL_EXT_buffer_reference : require

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;
layout (location = 2) flat in int inInstanceId;

//output write
layout (location = 0) out vec4 outFragColor;

layout(set = 0, binding = 0) uniform sampler2D textures[3];

#define QUAD_OPTIONS_TINT 1 << 0
struct QuadInfo {
    vec2 position;
    vec2 size;
    vec2 rotation_offset;
    vec2 uv_offset;
    vec2 uv_size;

    float rotation;
    uint color;
    uint texture_id;
    uint options;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};

layout(push_constant) uniform constants {
    QuadInfos instance_infos;
    vec2 screen_size;
} PushConstants;

// 1 << 32 - 1;
#define VERTEX_COLOR_ID 4294967295 
// 1 << 32 - 2;
#define SOLID_COLOR_ID 4294967294 

vec4 color_from_u32(uint color) {
    float a = float(color >> 24 & 0xFF) / 255.0;
    float b = float(color >> 16 & 0xFF) / 255.0;
    float g = float(color >> 8 & 0xFF) / 255.0;
    float r = float(color & 0xFF) / 255.0;
    return vec4(r, g, b, a);
}

void main() {
    QuadInfo qi = PushConstants.instance_infos.infos[inInstanceId];
    switch (qi.texture_id) {
      case VERTEX_COLOR_ID:
        outFragColor = vec4(inColor, 1.0);
        break;
      case SOLID_COLOR_ID:
        outFragColor = color_from_u32(qi.color);
        break;
      default:
        vec2 size = textureSize(textures[qi.texture_id], 0);
        vec2 uv_offset = qi.uv_offset / size;
        vec2 uv_size = qi.uv_size / size;
        vec4 color = texture(textures[qi.texture_id], inUV * uv_size + uv_offset).rrrr;
        if ((qi.options & QUAD_OPTIONS_TINT) == 1)
          color *= color_from_u32(qi.color);
        outFragColor = color;
        break;
    }
}
