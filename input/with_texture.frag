#version 330

layout (std140) uniform Material {
	vec4 diffuse;
	vec4 ambient;
	vec4 specular;
	vec4 emissive;
	float shininess;
	int texCount;
};

uniform	sampler2D texUnit;

in vec3 Normal;
in vec2 TexCoord;
out vec4 output;

void main()
{
	vec4 color;
	vec4 amb;
	float intensity;
	vec3 lightDir[7];
	vec3 n;
	
	lightDir[0] = normalize(vec3(1.0,1.0,2.0));	
	lightDir[1] = normalize(vec3(-2.0,0.0,-1.0));
	lightDir[2] = normalize(vec3(0.0,2.0,0.0));
	lightDir[3] = normalize(vec3(-1.0,-2.0,0.0));
	lightDir[4] = normalize(vec3(6.0,0.0,6.0));	
	lightDir[5] = normalize(vec3(0.0,6.0,6.0));

	n = normalize(Normal);	
	
	intensity = max(dot(lightDir[0],n),0.0) + max(dot(lightDir[1],n),0.0) + max(dot(lightDir[2],n),0.0) + max(dot(lightDir[3],n),0.0);
	
	if (texCount == 0) {
		color = diffuse;
		amb = ambient;
	}
	else {
		color = texture2D(texUnit, TexCoord);
		amb = color * 0.3;
	}
	output = (color * intensity) + amb;
	//output = vec4(texCount,0.0,0.0,1.0);

}
