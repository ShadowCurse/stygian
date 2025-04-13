#version 450

#extension GL_EXT_buffer_reference : require

#include "types.glsl"

//shader input
layout (location = 1) in vec3 in_world_pos;
layout (location = 2) in vec3 in_normal;
layout (location = 3) in vec2 in_uv;

//output write
layout (location = 0) out vec4 out_frag_color;

layout(set = 0, binding = 0) uniform sampler2D colorTex;

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

vec4 u32_to_vec4(uint v) {
  float r = float((v & 0xff)       >> 0) / 255;
  float g = float((v & 0xff00)     >> 8) / 255;
  float b = float((v & 0xff0000)   >> 16) / 255;
  return vec4(r, g, b, 0.0);
}

void main() {
    vec3 color = texture(colorTex, in_uv).xyz;

    vec3 view_dir =
         normalize(PushConstants.scene_push_constants.camera_info.position - in_world_pos);
    for (int i = 0; i < PushConstants.scene_push_constants.num_lights; i++) {
      Light light = PushConstants.scene_push_constants.lights.lights[i];

      float distance = distance(light.position, in_world_pos);
      float attenuation = 
                    1.0 / (light.constant + light.linear * distance + 
                    light.quadratic * (distance * distance));  

      vec3 light_dir = normalize(light.position - in_world_pos);
      vec3 half_dir = normalize(light_dir + view_dir);
      float spec = pow(max(dot(in_normal, half_dir), 0.0), 1.0);
      vec3 spec_color = u32_to_vec4(light.color).xyz * spec;

      color += spec_color;// * attenuation;
    }

    out_frag_color = vec4(color, 1.0);
}

