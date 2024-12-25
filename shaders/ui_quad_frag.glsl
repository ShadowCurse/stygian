#version 450

#extension GL_EXT_buffer_reference : require

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;
layout (location = 2) flat in int inInstanceId;

//output write
layout (location = 0) out vec4 outFragColor;

layout(set = 0, binding = 0) uniform sampler2D textures[2];

struct QuadInfo {
    uint color;
    uint texture_id;
    float __reserved0;
    float __reserved1;
    vec2 pos;
    vec2 size;
    float rotation;
    float __reserved2;
    vec2 rotation_offset;
    vec2 uv_offset;
    vec2 uv_size;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};

layout(push_constant) uniform constants {
    QuadInfos instance_infos;
} PushConstants;

// 1 << 32 - 1;
#define VERTEX_COLOR_ID 4294967295 
// 1 << 32 - 2;
#define SOLID_COLOR_ID 4294967294 

void main() {
    QuadInfo qi = PushConstants.instance_infos.infos[inInstanceId];
    switch (qi.texture_id) {
      case VERTEX_COLOR_ID:
        outFragColor = vec4(inColor, 1.0);
        break;
      case SOLID_COLOR_ID:
        float a = float(qi.color >> 24 & 0xFF) / 255.0;
        float b = float(qi.color >> 16 & 0xFF) / 255.0;
        float g = float(qi.color >> 8 & 0xFF) / 255.0;
        float r = float(qi.color & 0xFF) / 255.0;
        outFragColor = vec4(r, g, b, a);
        break;
      default:
        vec2 size = textureSize(textures[qi.texture_id], 0);
        vec2 uv_offset = qi.uv_offset / size;
        vec2 uv_size = qi.uv_size / size;
        outFragColor = vec4(texture(textures[qi.texture_id], inUV * uv_size + uv_offset).r);
        break;
    }
}
