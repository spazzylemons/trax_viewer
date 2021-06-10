#version 330 core

layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 normal;
layout (location = 2) in uvec3 packedColors;
layout (location = 3) in vec2 inUv;
layout (location = 4) in uint inIsTextured;

out vec2 uv;
out float facingRatio;
flat out uint colors[10];
flat out uint isTextured;

uniform vec3 cameraForward;
uniform mat4 view;
uniform mat4 projection;

void unpackColors() {
    // unpack the colors into an array of 10 bytes, from an array of 3 uints
    int j = 0; 
    for (int i = 0; i < 3; i++) {
        uint colorPack = packedColors[i];
        for (int k = 0; k < 4; k++) {
            if (j == colors.length()) return;
            colors[j++] = colorPack & 255u;
            colorPack >>= 8u;
        }
    }
}

void main() {
    gl_Position = projection * view * vec4(pos, 1.0);
    // srfx appears to light faces based on how much they face the camera, so we'll implement that
    // TODO take position into account
    facingRatio = max(0, dot(normal, cameraForward));
    unpackColors();
    // pass the rest down the pipeline
    uv = inUv;
    isTextured = inIsTextured;
}