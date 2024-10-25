#version 450

#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;

struct QuadInfo {
    mat4 transform;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};

layout(push_constant) uniform constants {
    QuadInfos instance_infos;
} PushConstants;

struct Vertex {
    vec3 position;
    float _unused;
    vec4 color;
}; 

Vertex[] vertices = {
  // Top
  {
    vec3(1.0, 1.0, 0.0),
    0.0,
    vec4(1.0, 0.0, 0.0, 1.0),
  },
  {
    vec3(1.0, -1.0, 0.0),
    0.0,
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec3(-1.0, -1.0, 0.0),
    0.0,
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  // Bottom
  {
    vec3(-1.0, -1.0, 0.0),
    0.0,
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  {
    vec3(-1.0, 1.0, 0.0),
    0.0,
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec3(1.0, 1.0, 0.0),
    0.0,
    vec4(0.0, 0.0, 1.0, 1.0),
  },
};

void main() {
    Vertex v = vertices[gl_VertexIndex];
    QuadInfo qi = PushConstants.instance_infos.infos[gl_InstanceIndex];

    vec4 new_position = qi.transform * vec4(v.position, 1.0);
    gl_Position = vec4(new_position.xy, 1.0, 1.0);

    outColor = v.color.xyz;
}
