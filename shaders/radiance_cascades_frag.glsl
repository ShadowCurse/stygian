#version 450
#extension GL_EXT_buffer_reference : require

//output write
layout (location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D cascade_textures[3];

struct Cascade {
    float point_offset;
    float ray_length;
    uint sample_size;
    uint samples_per_row;
    uint samples_per_column;
};

struct Circle {
  vec2 center;
  float radius;
  uint color;
};

layout(buffer_reference, std430) readonly buffer Cascades { 
    Cascade cascades[];
};

layout(buffer_reference, std430) readonly buffer Circles { 
    Circle circles[];
};

layout(push_constant) uniform constants {
    Cascades cascades;
    Circles circles;
    vec2 screen_size;
    uint circles_num;
    uint level;
    uint cmd;
} PushConstants;

ivec2 sample_position(uint cascade_idx, vec2 pixel_index) {
  Cascade cascade_info = PushConstants.cascades.cascades[cascade_idx];
  return ivec2(floor(pixel_index /
                     vec2(cascade_info.sample_size, cascade_info.sample_size)));
}

ivec2 element_position(uint cascade_idx, vec2 pixel_index, ivec2 sample_position) {
  Cascade cascade_info = PushConstants.cascades.cascades[cascade_idx];
  return ivec2(pixel_index - vec2(sample_position) * 
                             vec2(
                               cascade_info.sample_size,
                               cascade_info.sample_size
                             ));
}

int element_index(uint cascade_idx, ivec2 element_position) {
  Cascade cascade_info = PushConstants.cascades.cascades[cascade_idx];
  return element_position.x + element_position.y * int(cascade_info.sample_size);
}

vec4 u32_to_vec4(uint v) {
  float b = float((v & 0xff)       >> 0) / 255;
  float g = float((v & 0xff00)     >> 8) / 255;
  float r = float((v & 0xff0000)   >> 16) / 255;
  return vec4(r, g, b, 0.0);
}

vec4 cascade_value(uint cascade_idx, ivec2 sample_position, uint direction) {
  Cascade cascade_info = PushConstants.cascades.cascades[cascade_idx];
  uint offset_x = direction % cascade_info.sample_size;
  uint offset_y = direction / cascade_info.sample_size;
  vec2 coords = vec2(sample_position) *
                vec2(cascade_info.sample_size, cascade_info.sample_size) +
                vec2(offset_x, offset_y) +
                vec2(0.5, 0.5);
  coords /= PushConstants.screen_size;
  return texture(cascade_textures[cascade_idx], coords);
}

vec4 avg_in_direction(uint cascade_idx, ivec2 sample_position, uint direction) {
  vec4 color = vec4(0.0);
  uint start_direction = direction * 4;
  for (uint i = 0; i < 4; i++) {
    vec4 c = cascade_value(cascade_idx, sample_position, start_direction + i);
    color += c;
  }
  return color * 0.25;
}

vec4 avg_sample(uint cascade_idx, ivec2 sample_position) {
  Cascade cascade_info = PushConstants.cascades.cascades[cascade_idx];
  vec2 base = vec2(sample_position) * 
              vec2(cascade_info.sample_size, cascade_info.sample_size) +
              vec2(0.5, 0.5);

  vec2 c_00 = base;
  vec2 c_01 = base + vec2(0, 1);
  vec2 c_10 = base + vec2(1, 0);
  vec2 c_11 = base + vec2(1, 1);

  vec4 v_00 = texture(cascade_textures[cascade_idx], c_00 / PushConstants.screen_size);
  vec4 v_01 = texture(cascade_textures[cascade_idx], c_01 / PushConstants.screen_size);
  vec4 v_10 = texture(cascade_textures[cascade_idx], c_10 / PushConstants.screen_size);
  vec4 v_11 = texture(cascade_textures[cascade_idx], c_11 / PushConstants.screen_size);

  return (v_00 + v_01 + v_10 + v_11) * 0.25;
}

vec4 cmd_sample() {
  vec2 pixel_pos = gl_FragCoord.xy;
  uint cascade_idx = PushConstants.level;
  Cascade cascade_info = PushConstants.cascades.cascades[PushConstants.level];
  
  vec2 pixel_index = pixel_pos - vec2(0.5, 0.5);
  ivec2 sample_position = sample_position(cascade_idx, pixel_index);
  ivec2 element_position = element_position(cascade_idx, pixel_index, sample_position);
  int element_index = element_index(cascade_idx, element_position);

  float sample_points = cascade_info.sample_size * cascade_info.sample_size;
  float angle = 3.14 / sample_points + 
                3.14 / (sample_points / 2) * float(element_index);
  vec2 ray_direction = vec2(cos(angle), sin(angle));
  vec2 ray_origin = gl_FragCoord.xy + ray_direction * cascade_info.point_offset;

  vec4 color = vec4(0.0);
  for (uint i = 0; i < PushConstants.circles_num; i++) {
    Circle circle = PushConstants.circles.circles[i];
    float circle_radius_2 = circle.radius * circle.radius;
    vec2 to_circle = circle.center - ray_origin;
    if (dot(to_circle, to_circle) <= circle_radius_2) {
      color += u32_to_vec4(circle.color);
    } else {
      float t = dot(ray_direction, to_circle);
      if (0.0 < t) {
        float distance = t < cascade_info.ray_length ? t : cascade_info.ray_length;
        vec2 p = ray_origin + ray_direction * distance;
        vec2 p_to_circle = circle.center - p;
        if (dot(p_to_circle, p_to_circle) <= circle_radius_2) {
          color += u32_to_vec4(circle.color);
        } else {
          color += vec4(0.0, 0.0, 0.0, 1.0);
        }
      } else {
          color += vec4(0.0, 0.0, 0.0, 1.0);
      }
    }
  }
  return color;
}

vec4 cmd_merge() {
  vec2 pixel_pos = gl_FragCoord.xy;
  uint current_cascade_idx = PushConstants.level;
  uint next_cascade_idx = PushConstants.level + 1;
  Cascade current_cascade_info = PushConstants.cascades.cascades[current_cascade_idx];

  vec2 pixel_index = pixel_pos - vec2(0.5, 0.5);
  ivec2 sample_position = sample_position(current_cascade_idx, pixel_index);
  ivec2 element_position = element_position(current_cascade_idx, pixel_index, sample_position);
  int element_index = element_index(current_cascade_idx, element_position);

  vec4 current_p = cascade_value(current_cascade_idx, sample_position, element_index);

  uint next_x = min(
                    min(
                      sample_position.x + 1,
                      current_cascade_info.sample_size - 1
                    ) / 2,
                  current_cascade_info.sample_size
                );
  uint prev_x = uint(max(int(sample_position.x) - 1, 0)) / 2;
  uint next_y = min(
                    min(
                      sample_position.y + 1,
                      current_cascade_info.sample_size - 1
                    ) / 2,
                  current_cascade_info.sample_size
                );
  uint prev_y = uint(max(int(sample_position.y) - 1, 0)) / 2;

  float x_mix = (sample_position.x & 0x1) == 0 ? 0.75 : 0.25; 
  float y_mix = (sample_position.y & 0x1) == 0 ? 0.75 : 0.25; 

  vec4 p_00 = avg_in_direction(next_cascade_idx, ivec2(prev_x, prev_y), element_index);
  vec4 p_01 = avg_in_direction(next_cascade_idx, ivec2(prev_x, next_y), element_index);
  vec4 p_10 = avg_in_direction(next_cascade_idx, ivec2(next_x, prev_y), element_index);
  vec4 p_11 = avg_in_direction(next_cascade_idx, ivec2(next_x, next_y), element_index);

  vec4 p_00_01_mix = mix(p_00, p_10, x_mix);
  vec4 p_01_11_mix = mix(p_01, p_11, x_mix);
  vec4 mix = mix(p_00_01_mix, p_01_11_mix, y_mix);
  current_p.rgb += mix.rgb * current_p.a;
  current_p.a *= mix.a;
  return current_p;
}

vec4 cmd_draw() {
  vec2 pixel_pos = gl_FragCoord.xy;
  uint cascade_idx = PushConstants.level;

  vec2 pixel_index = pixel_pos - vec2(0.5, 0.5);
  ivec2 sample_position = sample_position(cascade_idx, pixel_index);

  return avg_sample(cascade_idx, sample_position);
}

void main() {
  switch (PushConstants.cmd) {
    case 0:
      out_color = cmd_sample();
      break;
    case 1:
      out_color = cmd_merge();
      break;
    case 2:
      out_color = cmd_draw();
      break;
  }
}
