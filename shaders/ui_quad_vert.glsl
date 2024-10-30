#version 450

#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;
layout (location = 1) out int outInstanceId;

struct QuadInfo {
    mat4 transform;
    vec3 color;
    uint type;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};

layout(push_constant) uniform constants {
    QuadInfos instance_infos;
} PushConstants;

struct Vertex {
    vec2 position;
    vec2 uv;
    vec4 color;
}; 

Vertex[] vertices = {
  // Top
  {
    vec2(1.0, 1.0),
    vec2(1.0, 0.0),
    vec4(1.0, 0.0, 0.0, 1.0),
  },
  {
    vec2(1.0, -1.0),
    vec2(1.0, 1.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 1.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  // Bottom
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 1.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  {
    vec2(-1.0, 1.0),
    vec2(0.0, 0.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec2(1.0, 1.0),
    vec2(1.0, 0.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
};

void main() {
    Vertex v = vertices[gl_VertexIndex];
    QuadInfo qi = PushConstants.instance_infos.infos[gl_InstanceIndex];

    vec4 new_position = qi.transform * vec4(v.position, 1.0, 1.0);
    gl_Position = vec4(new_position.xy, 1.0, 1.0);

    outColor = v.color.xyz;
    outInstanceId = gl_InstanceIndex;
}
