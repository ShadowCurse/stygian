#version 450

#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;

struct TriangleInfo {
    vec3 offset; 
    float _;
};

layout(buffer_reference, std430) readonly buffer TriangleInfos { 
    TriangleInfo infos[];
};

layout(push_constant) uniform constants {
    mat4 view_proj;
    TriangleInfos instance_infos;
} PushConstants;

struct Vertex {
    vec3 position;
    float _unused;
    vec4 color;
}; 

Vertex[] vertices = {
  {
    vec3(1.0, 1.0, 0.0),
    0.0,
    vec4(1.0, 0.0, 0.0, 1.0),
  },
  {
    vec3(0.0, -1.0, 1.0),
    0.0,
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec3(-1.0, 1.0, 1.0),
    0.0,
    vec4(0.0, 0.0, 1.0, 1.0),
  },
};

void main() {
    Vertex v = vertices[gl_VertexIndex];
    TriangleInfo ti = PushConstants.instance_infos.infos[gl_InstanceIndex];

    gl_Position = PushConstants.view_proj * vec4(v.position + ti.offset, 1.0f);
    outColor = v.color.xyz;
}
