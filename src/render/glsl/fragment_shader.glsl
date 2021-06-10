#version 330 core

in vec2 uv;
in float facingRatio;
flat in uint colors[10];
flat in uint isTextured;

out vec4 fragColor;

uniform vec3 palette[256];
uniform usampler2D tex;

void main() {
    if (isTextured != 0u) {
        // if textured:
        // select palette index from texture
        uint color = texture(tex, uv).r;
        if (color == 0u) {
            // discard if transparent
            discard;
        } else {
            // add to color to select which 16 colors to use
            fragColor = vec4(palette[(colors[0] + color) & 255u], 1.0);
        }
    } else {
        // if not textured:
        // select color from set based on how much the face is facing the camera
        uint color = colors[min(9u, uint(10.0 * facingRatio))];
        fragColor = vec4(palette[color], 1.0);
    }
}