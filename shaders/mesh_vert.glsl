#version 450

layout (location = 0) out vec3 outColor;

struct Vertex {
    vec3 position;
    vec4 color;
}; 

Vertex[] vertices = {
  {
    vec3(1.0, 1.0, 0.0),
    vec4(1.0, 0.0, 0.0, 1.0),
  },
  {
    vec3(0.0, -1.0, 1.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec3(-1.0, 1.0, 1.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },

};

void main() {
    Vertex v = vertices[gl_VertexIndex];

    gl_Position = vec4(v.position, 1.0f);
    outColor = v.color.xyz;
}
