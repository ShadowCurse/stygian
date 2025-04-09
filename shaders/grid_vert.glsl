#version 450

layout (location = 1) out vec3 out_near;
layout (location = 2) out vec3 out_far;

layout(push_constant) uniform constants {
    mat4 view;
    mat4 proj;
} PushConstants;

vec3 grid_planes[6] = vec3[](
    vec3(1, 1, 0), vec3(-1, -1, 0), vec3(-1, 1, 0),
    vec3(-1, -1, 0), vec3(1, 1, 0), vec3(1, -1, 0)
);

vec3 clip_to_world(vec3 point) {
  mat4 inv_view = inverse(PushConstants.view);
  mat4 inv_proj = inverse(PushConstants.proj);
  vec4 world = inv_view * inv_proj * vec4(point, 1.0);
  return world.xyz / world.w;
}

void main() {
    vec3 point = grid_planes[gl_VertexIndex];
    vec3 world_near = clip_to_world(vec3(point.xy, 1.0));
    vec3 world_far = clip_to_world(vec3(point.xy, 0.0));

    out_near = world_near;
    out_far = world_far;
    gl_Position = vec4(grid_planes[gl_VertexIndex], 1.0);
}
