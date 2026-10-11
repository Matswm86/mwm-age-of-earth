shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Flat marks on the ground (MultiMesh of a 2 x 2 m quad, scaled per instance):
// INSTANCE_CUSTOM.x = 0 team disc (soft fill + dark outline, DESIGN 4: also the contact shadow),
// 1 selection ring / move marker (6 cm line in a 2 px dark outline), 2 placement footprint.
// COLOR = instance colour, alpha = strength.

#include "res://shaders/ground_mark.gdshaderinc"
