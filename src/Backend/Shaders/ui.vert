#version 460

//* UI vertex shader.
//
//* The GUI works in pixels with the origin at the top left and y growing
//* down, so the pixel position is mapped to clip space here: x maps
//* -1..1 left to right, y maps 1..-1 top to bottom.

//* SDL3 GPU resource layout for vertex shaders:
//*   set 0 = samplers and storage resources
//*   set 1 = uniform data, in SDL slot order
//* The uniform buffer is pushed to slot 0, so it is binding 0 of set 1.
layout(set = 1, binding = 0) uniform UBO {
    vec2 viewport;   // the drawable size in pixels
};

layout(location=0) in vec2 position;
layout(location=1) in vec2 tex_coord;
layout(location=2) in vec4 colour;
//* The shape of the fragment: the kind, the radius of the corners and
//* the half size of the quad the vertex belongs to.
layout(location=3) in vec4 shape;
//* Where the vertex sits inside its quad, measured from the middle of
//* the quad. The fragment shader uses it to work out how far a
//* fragment is from a rounded corner.
layout(location=4) in vec2 local;

layout(location=0) out vec2 uv;
layout(location=1) out vec4 v_colour;
layout(location=2) out vec4 v_shape;
layout(location=3) out vec2 v_local;

void main() {
    vec2 ndc = vec2(
        position.x / viewport.x * 2.0 - 1.0,
        1.0 - position.y / viewport.y * 2.0
    );
    gl_Position = vec4(ndc, 0.0, 1.0);
    uv = tex_coord;
    v_colour = colour;
    v_shape = shape;
    v_local = local;
}
