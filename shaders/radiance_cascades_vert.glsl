#version 450

struct Vertex {
    vec2 position;
}; 

vec2[] vertices = {
  // Top
  vec2(1.0, 1.0),
  vec2(1.0, -1.0),
  vec2(-1.0, -1.0),
  // Bottom
  vec2(-1.0, -1.0),
  vec2(-1.0, 1.0),
  vec2(1.0, 1.0),
};

void main() {
    vec2 v = vertices[gl_VertexIndex];
    gl_Position = vec4(v, 0.0, 1.0);
}
