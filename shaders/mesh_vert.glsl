#version 450

#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;

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

layout(push_constant) uniform constants {
    mat4 view_proj;
    Vertices vertices;
} PushConstants;

void main() {
    Vertex v = PushConstants.vertices.vertices[gl_VertexIndex];
    gl_Position = PushConstants.view_proj * vec4(v.position, 1.0f);
    outColor = vec3(1.0);
}
