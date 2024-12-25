#version 450

#extension GL_EXT_buffer_reference : require

layout (location = 0) out vec3 outColor;
layout (location = 1) out vec2 outUV;
layout (location = 2) out int outInstanceId;

struct QuadInfo {
    vec3 position;
    float __reserved0;

    vec2 size;
    vec2 rotation_offset;
    vec2 uv_offset;
    vec2 uv_size;

    float rotation;
    uint color;
    uint texture_id;
    float __reserved1;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};

layout(push_constant) uniform constants {
    QuadInfos instance_infos;
    vec2 screen_size;
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
    vec2(1.0, 1.0),
    vec4(1.0, 0.0, 0.0, 1.0),
  },
  {
    vec2(1.0, -1.0),
    vec2(1.0, 0.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 0.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  // Bottom
  {
    vec2(-1.0, -1.0),
    vec2(0.0, 0.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
  {
    vec2(-1.0, 1.0),
    vec2(0.0, 1.0),
    vec4(0.0, 1.0, 0.0, 1.0),
  },
  {
    vec2(1.0, 1.0),
    vec2(1.0, 1.0),
    vec4(0.0, 0.0, 1.0, 1.0),
  },
};

void main() {
    Vertex v = vertices[gl_VertexIndex];
    QuadInfo qi = PushConstants.instance_infos.infos[gl_InstanceIndex];
    vec2 screen_size = PushConstants.screen_size;

    float c = cos(qi.rotation);
    float s = sin(qi.rotation);
    mat2 rotation = mat2(c, -s, s, c);
    vec2 vertex_position = rotation * v.position;

    vec2 qp = qi.position.xy + qi.rotation_offset + rotation * qi.rotation_offset;
    vec2 quad_pos = (qp / (screen_size / 2.0)) - vec2(1.0);
    vec2 quad_size = qi.size / screen_size;
    vec4 new_position = vec4(
        (vertex_position * quad_size + quad_pos), 
        1.0,
        1.0);
    gl_Position = vec4(new_position.xy, 1.0, 1.0);

    outColor = v.color.xyz;
    outUV = v.uv;
    outInstanceId = gl_InstanceIndex;
}
