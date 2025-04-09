#version 450

layout (location = 1) in vec3 in_near;
layout (location = 2) in vec3 in_far;

layout (location = 0) out vec4 out_color;

layout(push_constant) uniform constants {
    mat4 view;
    mat4 proj;
} PushConstants;

#define AXIS_LINE_WIDTH 1.0
#define DEFAULT_LINE_COLOR vec3(0.2, 0.2, 0.2)

// world_pos - world position of the fragment
// scale - distance between lines, high == more distance
vec4 grid_point_color(vec3 world_pos, float scale) {
  vec2 coord = world_pos.xy / scale;
  // calculate the sum of derivatives for x and y for both coords
  vec2 d = fwidth(coord);
  // subtract 0.5 from coord to shift grid for half the square size
  // then subtract 0.5 again to move value into -0.5..0.5 range
  // take only positive side with abs() (so basically only original 0.5..1.0 values remain and
  // are mapped to 0.0..0.5 range)
  vec2 grid = abs(fract(coord - 0.5) - 0.5) / d;
  float line = min(grid.x, grid.y);
  float min_x = min(d.x, 1.0);
  float min_y = min(d.y, 1.0);
  vec4 color = vec4(DEFAULT_LINE_COLOR, 1.0 - min(line, 1.0));
  // x axis
  if(-AXIS_LINE_WIDTH * min_y < world_pos.y && world_pos.y < AXIS_LINE_WIDTH * min_y)
      color.x = 1.0;
  // y axis
  if(-AXIS_LINE_WIDTH * min_x < world_pos.x && world_pos.x < AXIS_LINE_WIDTH * min_x)
      color.y = 1.0;
  return color;
}

float depth(vec3 world_pos) {
  vec4 clip = PushConstants.proj * PushConstants.view * vec4(world_pos, 1.0);
  return clip.z / clip.w;
}

void main() {
    float t = -in_near.z / (in_far.z - in_near.z);
    vec3 world_pos = in_near + t * (in_far - in_near);
    float depth = depth(world_pos);

    float lod_level = max(1.0, log(in_near.z) / log(10.0));
    float lod_fade = fract(lod_level);

    // high dencity
    float lod_0 = pow(10.0, floor(lod_level)) / 10.0;
    // low dencity
    float lod_1 = lod_0 * 10.0;

    vec4 lod_0_color = grid_point_color(world_pos, lod_0);
    lod_0_color.a *= 1.0 - lod_fade;

    vec4 lod_1_color = grid_point_color(world_pos, lod_1);
    lod_1_color.a *= lod_fade;

    vec4 color = (lod_0_color + lod_1_color) * float(t > 0.0);
    color.a *= depth * 100.0;

    gl_FragDepth = depth;
    out_color = color;
}
