#version 450

#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;
layout (location = 1) out vec2 outUV;

struct Vertex {
    vec3 position;
    float uv_x;
    vec3 normal;
    float uv_y;
    vec4 color;
}; 

layout(buffer_reference, std430) readonly buffer Vertices { 
    Vertex vertices[];
};

struct MeshInfo {
  mat4 transform;
};

layout(buffer_reference, std430) readonly buffer MeshInfos { 
    MeshInfo infos[];
};

layout(push_constant) uniform constants {
    mat4 view_proj;
    Vertices vertices;
    MeshInfos mesh_infos;
} PushConstants;

void main() {
    Vertex v = PushConstants.vertices.vertices[gl_VertexIndex];
    mat4 transform = PushConstants.mesh_infos.infos[gl_InstanceIndex].transform;

    gl_Position = PushConstants.view_proj * transform * vec4(v.position, 1.0f);
    outColor = vec3(1.0);
    outUV = vec2(v.uv_x, v.uv_y);
}
