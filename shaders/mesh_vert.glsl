#version 450

#extension GL_EXT_buffer_reference : require

#include "types.glsl"

layout (location = 1) out vec3 out_world_pos;
layout (location = 2) out vec3 out_normal;
layout (location = 3) out vec2 out_uv;

struct ScenePushConstants {
    CameraInfo camera_info;
    Lights lights;
    uint num_lights;
};

layout(push_constant) uniform constants {
    Vertices vertices;
    MeshInfos mesh_infos;
    ScenePushConstants scene_push_constants;
} PushConstants;

void main() {
    Vertex v = PushConstants.vertices.vertices[gl_VertexIndex];
    mat4 transform = PushConstants.mesh_infos.infos[gl_InstanceIndex].transform;
    vec4 world_pos = transform * vec4(v.position, 1.0);

    mat3 rotation = mat3(transform);
    vec3 world_normal = rotation * v.normal;

    out_uv = vec2(v.uv_x, v.uv_y);
    out_world_pos = world_pos.xyz;
    out_normal = world_normal;
    gl_Position = PushConstants.scene_push_constants.camera_info.projection *
                  PushConstants.scene_push_constants.camera_info.view *
                  world_pos;
}
