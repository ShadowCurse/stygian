#version 450

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;

//output write
layout (location = 0) out vec4 outFragColor;

layout(set = 0, binding = 0) uniform sampler2D colorTex;

void main() {
    vec3 color = texture(colorTex, inUV).xyz;
    outFragColor = vec4(color, 1.0);
}

