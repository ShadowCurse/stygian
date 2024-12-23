#version 450

#extension GL_EXT_buffer_reference : require

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;
layout (location = 2) flat in int inInstanceId;

//output write
layout (location = 0) out vec4 outFragColor;

layout(set = 0, binding = 0) uniform sampler2D colorTex;
layout(set = 0, binding = 1) uniform sampler2D fontTex;

struct QuadInfo {
    uint color;
    float __reserved0;
    float __reserved1;
    uint type;
    vec2 pos;
    vec2 size;
    float rotation;
    float __reserved2;
    vec2 rotation_center;
    vec2 uv_offset;
    vec2 uv_size;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};

layout(push_constant) uniform constants {
    QuadInfos instance_infos;
} PushConstants;

void main() {
    QuadInfo qi = PushConstants.instance_infos.infos[inInstanceId];

    if (qi.type == 0) {
      outFragColor = vec4(inColor, 1.0);
    } else if (qi.type == 1) {
      float a = float(qi.color >> 24 & 0xFF) / 255.0;
      float b = float(qi.color >> 16 & 0xFF) / 255.0;
      float g = float(qi.color >> 8 & 0xFF) / 255.0;
      float r = float(qi.color & 0xFF) / 255.0;
      outFragColor = vec4(r, g, b, a);
    } else if (qi.type == 2) {
      outFragColor = texture(colorTex, inUV);
    } else {
      vec2 size = textureSize(fontTex, 0);
      vec2 uv_offset = qi.uv_offset / size;
      vec2 uv_size = qi.uv_size / size;
      outFragColor = vec4(texture(fontTex, inUV * uv_size + uv_offset).r);
    }
}
