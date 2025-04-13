struct Light {
  vec3 position;
  uint color;
  float constant;
  float linear;
  float quadratic;
};

layout(buffer_reference, std430) readonly buffer Lights { 
    Light lights[];
};

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

layout(buffer_reference, std430) readonly buffer CameraInfo { 
  mat4 view;
  mat4 projection;
  vec3 position;
};

#define QUAD_OPTIONS_TINT 1 << 0
struct QuadInfo {
    vec2 position;
    vec2 size;
    vec2 rotation_offset;
    vec2 uv_offset;
    vec2 uv_size;

    float rotation;
    uint color;
    uint texture_id;
    uint options;
};

layout(buffer_reference, std430) readonly buffer QuadInfos { 
    QuadInfo infos[];
};
