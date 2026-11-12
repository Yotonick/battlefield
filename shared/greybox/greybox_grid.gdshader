// Greybox-материал: сетка 1 м (тонкие линии) и 5 м (толстые) в мировых координатах.
// Не нужен ни один текстурный файл; масштаб одинаковый на любом объекте.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.55, 0.55, 0.55);
uniform vec3 line_color : source_color = vec3(0.32, 0.32, 0.32);
uniform float cell_size = 1.0;
uniform float major_every = 5.0;
uniform float line_width = 0.015;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float grid(vec2 p, float size, float width) {
	// Расстояние (в метрах) до ближайшей линии сетки.
	vec2 dist = abs(fract(p / size + 0.5) - 0.5) * size;
	vec2 aa = fwidth(p);
	vec2 lines = 1.0 - smoothstep(vec2(width) - aa, vec2(width) + aa, dist);
	return max(lines.x, lines.y);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 p;
	if (n.y >= n.x && n.y >= n.z) {
		p = world_pos.xz;
	} else if (n.x >= n.z) {
		p = world_pos.zy;
	} else {
		p = world_pos.xy;
	}
	float minor = grid(p, cell_size, line_width) * 0.6;
	float major = grid(p, cell_size * major_every, line_width * 2.0);
	ALBEDO = mix(base_color, line_color, max(minor, major));
	ROUGHNESS = 0.92;
}
