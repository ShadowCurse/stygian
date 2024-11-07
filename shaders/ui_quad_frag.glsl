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
    vec3 color;
    uint type;
    vec2 pos;
    vec2 scale;
    vec2 uv_pos;
    vec2 uv_scale;
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
      outFragColor = vec4(qi.color, 1.0);
    } else if (qi.type == 2) {
      outFragColor = texture(colorTex, inUV);
    } else {
      outFragColor = texture(fontTex, inUV * qi.uv_scale + qi.uv_pos);
    }
}
