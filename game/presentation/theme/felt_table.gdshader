// Mesa de casino: sala oscura, baranda acolchada de madera, filete dorado y paño verde
// con viñeta y textura de tela. Todo se calcula por píxel (sin texturas) y con bordes
// antialiasados, así escala a cualquier resolución.
shader_type canvas_item;

uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float margin = 10.0;
uniform float rail_width = 28.0;
uniform float corner_radius = 200.0;
uniform vec4 room_color : source_color = vec4(0.04, 0.06, 0.05, 1.0);
uniform vec4 rail_dark : source_color = vec4(0.20, 0.10, 0.05, 1.0);
uniform vec4 rail_light : source_color = vec4(0.47, 0.27, 0.13, 1.0);
uniform vec4 inlay_color : source_color = vec4(0.83, 0.69, 0.22, 1.0);
uniform vec4 felt_center : source_color = vec4(0.15, 0.46, 0.28, 1.0);
uniform vec4 felt_edge : source_color = vec4(0.05, 0.22, 0.13, 1.0);

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * rect_size;
	vec2 c = rect_size * 0.5;
	vec2 hs = c - vec2(margin);
	float r = min(corner_radius, min(hs.x, hs.y));
	float d = sd_round_box(p - c, hs, r);        // < 0 dentro de la mesa
	float fd = d + rail_width;                   // < 0 dentro del paño

	// Sala: oscura, con la sombra de la mesa alrededor.
	vec3 room = room_color.rgb * (1.0 - 0.3 * length((p - c) / c));
	room *= mix(0.45, 1.0, smoothstep(0.0, 36.0, d));

	// Baranda: degradado redondeado (luz en el centro del acolchado) y veta suave.
	float t = clamp(-d / rail_width, 0.0, 1.0);
	vec3 rail = mix(rail_dark.rgb, rail_light.rgb, pow(sin(t * 3.14159), 1.5));
	rail *= 0.94 + 0.06 * sin(p.x * 0.08 + sin(p.y * 0.05) * 3.0);

	// Paño: viñeta (más claro al centro), grano de tela y sombra junto a la baranda.
	vec2 q = (p - c) / hs;
	float v = length(q * vec2(0.9, 1.0));
	vec3 felt = mix(felt_center.rgb, felt_edge.rgb, smoothstep(0.05, 1.1, v));
	felt *= 0.965 + 0.07 * hash(floor(p));
	felt *= mix(0.62, 1.0, smoothstep(0.0, 22.0, -fd));

	vec3 col = room;
	col = mix(col, rail, smoothstep(0.75, -0.75, d));
	col = mix(col, felt, smoothstep(0.75, -0.75, fd));

	// Filete dorado impreso en el paño, a 12 px de la baranda.
	float line = abs(fd + 12.0);
	col = mix(col, inlay_color.rgb, (1.0 - smoothstep(0.4, 1.4, line)) * 0.8);

	COLOR = vec4(col, 1.0);
}
