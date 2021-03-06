#version 300 es
precision mediump float;

/**
 * Author: René Warnking
 * Copyright 2019 René Warnking
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

///////////////////////////////////////////////////////////////////////////////
// defines
///////////////////////////////////////////////////////////////////////////////
// 0 - Sphere
// 1 - Cubes (incorrect shadows)
#define OBJ_TYPE 0
// 0 - no debug
// 1 - position
// 2 - normal
// 3 - obj color
// 4 - shadow value
// 5 - use debugVec
#define DEBUG 0

#define SHADOW_ITER_COUNT 10
#define REFLECTION_ITER_COUNT 5
#define MATERIAL_COUNT 8
#define MATERIAL_COUNT_F 8.0
#define BORDER_MAT 0

#define phong_ambient vec3(0.2)
#define phong_diffuse vec3(1.0)
#define phong_specular vec3(1.0)
#define phong_shine 16.0

#define PI 3.14159265359

///////////////////////////////////////////////////////////////////////////////
// constant variables
///////////////////////////////////////////////////////////////////////////////
const int MAX_MARCHING_STEPS = 255;
const int MAX_SHADOW_MARCHING_STEPS = 55;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float EPSILON = 0.001;
const vec3 BOX_DIMS = vec3(1.0); // TODO capital letters
const float EFFECT_RADIUS = 1.0;

///////////////////////////////////////////////////////////////////////////////
// uniforms
///////////////////////////////////////////////////////////////////////////////
uniform vec2 uResolution;
uniform float uTime;

// background effect
uniform float uEffectTime;

uniform vec3 uCameraPos;
uniform float uWidth;
uniform float uHeight;

uniform sampler2D uBoardTex;

out vec4 oColor;

///////////////////////////////////////////////////////////////////////////////
// globals
///////////////////////////////////////////////////////////////////////////////
vec2 dimsHalf = vec2(0.0);
#if DEBUG == 5
vec3 debugVec = vec3(0.0);
#endif

///////////////////////////////////////////////////////////////////////////////
// structs
///////////////////////////////////////////////////////////////////////////////
struct material {
    vec3 color;
    float reflection;
};

material materials[MATERIAL_COUNT] = material[](
    material(vec3(0.1, 0.2, 0.4), 0.0), // BorderMaterial
    material(vec3(0.8, 0.0, 0.1), 0.1),
    material(vec3(0.75, 1.0, 0.0), 0.4),
    material(vec3(0.1, 0.7, 0.1), 0.7),
    material(vec3(0.3, 0.8, 0.9), 0.1),
    material(vec3(0.0, 0.2, 0.9), 0.2),
    material(vec3(0.4, 0.0, 0.6), 0.1),
    material(vec3(1.0, 1.0, 1.0), 0.3)
);

struct hit {
    vec3 obj_center;
    int mat_id;
    vec3 hit_p;
    vec3 dim;
} l_hit;

///////////////////////////////////////////////////////////////////////////////
// Helper Functions
///////////////////////////////////////////////////////////////////////////////
/**
 * Normalized direction to march in from the eye point for a single pixel.
 *
 * fieldOfView: vertical field of view in degrees
 * fragCoord: the x,y coordinate of the pixel in the output image
 */
vec3 rayDirection(float fieldOfView, vec2 fragCoord)
{
    vec2 xy = fragCoord - uResolution * 0.5;
    float which = uResolution.x / uWidth < uResolution.y / uHeight ?
        uResolution.x :
    	uResolution.y;
    float z = which / tan(radians(fieldOfView) * 0.5);
    return normalize(vec3(xy, -z));
}

vec3 hslColor(float hue, float sat, float light)
{
    // satuartion = 1.0, light = 0.5
    float C = (1.0 - abs(2.0 * light - 1.0)) * sat;
    float X = C * (1.0 - abs(mod(hue / 60.0, 2.0) - 1.0));
    float M = light - C * 0.5;

    vec3 color = vec3(M);

    if (hue < 60.0) {
        color.r += C;
        color.g += X;
        color.b += 0.0;
    } else if (hue < 120.0) {
        color.r += X;
        color.g += C;
        color.b += 0.0;
    } else if (hue < 180.0) {
        color.r += 0.0;
        color.g += C;
        color.b += X;
    } else if (hue < 240.0) {
        color.r += 0.0;
        color.g += X;
        color.b += C;
    } else if (hue < 300.0) {
        color.r += X;
        color.g += 0.0;
        color.b += C;
    } else {
        color.r += C;
        color.g += 0.0;
        color.b += X;
    }
    return color;
}

vec3 rainbowColor(float sat, float light)
{
    //float hue = sin(uTime * 0.25) * 180.0 + 180.0;
    float hue = mod(uTime * 20.0, 360.0);

    return hslColor(hue, sat, light);
}

///////////////////////////////////////////////////////////////////////////////
// Signed Distance Functions
///////////////////////////////////////////////////////////////////////////////
float differenceSDF(float distA, float distB)
{
    return max(distA, -distB);
}

/**
 * Signed distance function for a sphere centered at the origin with radius 1.0;
 */
float sphereSDF(vec3 samplePoint, vec3 spherePos)
{
    return length(samplePoint - spherePos) - 0.5;
}

float boxSDF(vec3 samplePoint, vec3 boxPos, vec3 boxDim)
{
    vec3 q = abs(samplePoint - boxPos) - boxDim;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float borderSDF(vec3 samplePoint, float planeDist)
{
    float r1 = boxSDF(
        samplePoint,
        vec3(0.0, 0.0, planeDist),
        vec3(dimsHalf + 1.0, 0.5)
    );

	float r2 = boxSDF(
        samplePoint,
        vec3(0.0, 0.0, planeDist),
        vec3(dimsHalf.xy, 1.0)
    );

    return differenceSDF(r1, r2);
}

float effectSDF(vec3 p, vec3 pos)
{
    float t = 2.5 * uEffectTime;
    // vec3 m = vec3(mod(abs(p.xyz), 5.0));
    float q = sin(t * p.x) * sin(t * p.y) * sin(t * p.z);
    return length(p - pos) - 7.5 + q;
}

///////////////////////////////////////////////////////////////////////////////
// Draw Parts
///////////////////////////////////////////////////////////////////////////////
float drawBorder(vec3 samplePoint, float planeDist)
{
    float min_d = MAX_DIST;
	float tmp = borderSDF(samplePoint, planeDist);

    if (min_d > tmp)
    {
        min_d = tmp;
        l_hit.obj_center = vec3(0.0, 0.0, planeDist);
        l_hit.hit_p = samplePoint;
        l_hit.mat_id = BORDER_MAT;
        l_hit.dim = vec3(dimsHalf + 1.0, 0.5);
    }

    return min_d;
}

float drawField(vec3 samplePoint, vec2 rayMul,
                float material, float planeDist, float dist)
{
	float min_d = dist;

    if (material > 0.0)
    {
        vec3 stonePos = vec3(floor(rayMul) + vec2(0.5), planeDist);
#if OBJ_TYPE == 0
        float tmp_d = sphereSDF(samplePoint, stonePos);
#else
        float tmp_d = boxSDF(samplePoint, stonePos, vec3(0.5));
#endif
        if (tmp_d < min_d)
        {
            min_d = tmp_d;
            l_hit.obj_center = stonePos;
            l_hit.mat_id = int(material * (MATERIAL_COUNT_F - 1.0)) + 1;
        }
        // interestingly enough this does not improve but rather
        // decrease performance
        //if (min_d < EPSILON)
        //    return min_d;
    }
    l_hit.hit_p = samplePoint;
    return min_d;
}

float boundRaymarching(vec3 camera, vec3 ray, float planeDist)
{
    float depth = 0.0;

    float zback = (planeDist - BOX_DIMS.z * 0.5) / ray.z;
    vec2 rayMulB = ray.xy * zback;

    float zfront = (planeDist + BOX_DIMS.z * 0.5) / ray.z;
    vec2 rayMulF = ray.xy * zfront;

    // If the ray does not hit within the border area
    // there cant be any hits of the field
    if (round(rayMulF.x - 0.5) <= dimsHalf.x &&
        round(rayMulF.x + 0.5) >= -dimsHalf.x &&
        round(abs(rayMulF.y) - 0.5) <= dimsHalf.y &&
        round(rayMulF.y + 0.5) >= -dimsHalf.y
       )
    {
        ivec2 uvB = ivec2(rayMulB + dimsHalf);
        ivec2 uvF = ivec2(rayMulF + dimsHalf);

            //debugVec = vec3(0.0, 0.0, 1.0);


        float[2] materials;
        vec2[2] positions;
		// Since the area in which the stones need to be sampled is
        // smaller then the field we can make an additional check
        // by only checking the front intersection, since the bottom
        // one can not be hit, if the front intersection is not inside the area
        if (rayMulF.x > -dimsHalf.x && rayMulF.y > -dimsHalf.y &&
           	 rayMulF.x < dimsHalf.x && rayMulF.y < dimsHalf.y)
        {
            materials[0] = texelFetch(uBoardTex, uvB, 0).x;
            materials[1] = texelFetch(uBoardTex, uvF, 0).x;

            positions[0] = rayMulB;
            positions[1] = rayMulF;
        }

        float dist = MAX_DIST;
        for (int i = 0; i < MAX_MARCHING_STEPS && depth < MAX_DIST; i++)
        {
            dist = drawBorder(camera + depth * ray, planeDist);

            for (int j = 0; j < 2; j++)
            {
                dist = min(dist, drawField(
                    camera + depth * ray, positions[j], materials[j], planeDist, dist
                ));
            }
            if (dist < EPSILON)
                return 0.0;
            depth += dist;
        }
    }

    return MAX_DIST;
}

///////////////////////////////////////////////////////////////////////////////
// Lighting
///////////////////////////////////////////////////////////////////////////////
vec3 estimateNormal(vec3 p, vec3 position, int mat)
{
    if (mat == BORDER_MAT)
    {
        return normalize(vec3(
            borderSDF(vec3(p.x + EPSILON, p.y, p.z), position.z) -
            borderSDF(vec3(p.x - EPSILON, p.y, p.z), position.z),
            borderSDF(vec3(p.x, p.y + EPSILON, p.z), position.z) -
            borderSDF(vec3(p.x, p.y - EPSILON, p.z), position.z),
            borderSDF(vec3(p.x, p.y, p.z + EPSILON), position.z) -
            borderSDF(vec3(p.x, p.y, p.z - EPSILON), position.z)
        ));
    }
    else
    {
#if OBJ_TYPE == 0
        return normalize(vec3(
            sphereSDF(vec3(p.x + EPSILON, p.y, p.z), position) -
            sphereSDF(vec3(p.x - EPSILON, p.y, p.z), position),
            sphereSDF(vec3(p.x, p.y + EPSILON, p.z), position) -
            sphereSDF(vec3(p.x, p.y - EPSILON, p.z), position),
            sphereSDF(vec3(p.x, p.y, p.z + EPSILON), position) -
            sphereSDF(vec3(p.x, p.y, p.z - EPSILON), position)
        ));
#else
        return normalize(vec3(
            boxSDF(vec3(p.x + EPSILON, p.y, p.z), position, vec3(0.5)) -
            boxSDF(vec3(p.x - EPSILON, p.y, p.z), position, vec3(0.5)),
            boxSDF(vec3(p.x, p.y + EPSILON, p.z), position, vec3(0.5)) -
            boxSDF(vec3(p.x, p.y - EPSILON, p.z), position, vec3(0.5)),
            boxSDF(vec3(p.x, p.y, p.z + EPSILON), position, vec3(0.5)) -
            boxSDF(vec3(p.x, p.y, p.z - EPSILON), position, vec3(0.5))
        ));
#endif
    }
}

vec3 phongOfPoint(vec3 light_pos, vec3 cam_pos, vec3 hit_point, vec3 normal)
{
    vec3 light_dir = normalize(light_pos - hit_point);
    vec3 view_dir = normalize(cam_pos - hit_point);

    float light_intensity = max(dot(normal, light_dir), 0.0);

    if (light_intensity > 0.0)
    {
        vec3 diffuse = light_intensity * phong_diffuse;

        float specular_strength = 1.0;
        vec3 reflect_dir = reflect(-light_dir, normal);

        float spec = pow(max(dot(view_dir, reflect_dir), 0.0), 32.0);
        vec3 specular = specular_strength * spec * phong_specular;

        return diffuse + specular;
    }
	return vec3(0.0);
}

////////////////////////////////////////////////////////
// Shadows
////////////////////////////////////////////////////////
// http://www.cse.yorku.ca/~amana/research/grid.pdf
float shadowRaymarching(vec3 camera, vec3 ray, float planeDist, vec3 light_pos)
{
    float light_dist = length(light_pos - camera);

    vec2 start = camera.xy;
    vec2 end = light_pos.xy;

    // Direction from point on stone to the lightsource
    vec2 dir = end - start;

    // If distance to small adjust it to avoid division by 0
    // This is done componentwise to allow for axis aligned vectors (e.g. 1,0)
    if (dir.x <= EPSILON && dir.x >= -EPSILON)
        dir.x = EPSILON;
    if (dir.y <= EPSILON && dir.y >= -EPSILON)
        dir.y = EPSILON;
    // If distance short return early
    if (light_dist <= EPSILON)
        return light_dist;
    vec2 dirVec = normalize(dir);

    // Run a bresenham algorithm to iterate all stones on the path of the ray
    vec2 step = sign(dir);
    dirVec = abs(dirVec);

    // Calculate the distance from the start point
    // to the edges of a stonefield which could intersect the ray
    // This is dependend on the ray direction.
    vec2 tMax = fract(start);
    if (step.x > 0.0)
        tMax.x = BOX_DIMS.x - tMax.x;
    if (step.y > 0.0)
        tMax.y = BOX_DIMS.y - tMax.y;
    tMax /= dirVec;

    // Calculate the offset by which the point is moved to reach the next stonepos
    vec2 tDelta = BOX_DIMS.xy / dirVec;

    // As long as the stepcount is not exceeded and the lightpos is not reached continue
    for (int steps = 0; (start.x * step.x < end.x * step.x || start.y * step.y < end.y * step.y) &&
         steps < SHADOW_ITER_COUNT; steps++)
    {
        // Advance the start position, this depends on the slope of the dirVec (lower first)
        // Increase the tDelta to switch direction as soon as necessary
        if (tMax.x < tMax.y)
        {
            tMax.x += tDelta.x;
            start.x += step.x;
        }
        else
        {
            tMax.y += tDelta.y;
            start.y += step.y;
        }

        // Use the position to calculate the texture coords
        // these need to be adjusted to be only positive
        ivec2 uv = ivec2(floor(start) + dimsHalf);

        float material = texelFetch(uBoardTex, uv, 0).x;
        // If the position is occupied check whether the ray actually hits this stone
        if (material > 0.0)
    	{
        	vec3 newPos = vec3(floor(start) + vec2(0.5), planeDist);

            float depth = 0.0;
            float dist = light_dist;
            // TODO max(boxdims) instead of lightdist?
            for (int i = 0; i < MAX_SHADOW_MARCHING_STEPS && depth < light_dist; i++)
            {

#if OBJ_TYPE == 0
            	dist = sphereSDF(camera + depth * ray, newPos);
#else
                dist = boxSDF(camera + depth * ray, newPos, vec3(0.5));
#endif
                // If the distance is small then the stone was hit
                // otherwise continue following the ray
                if (dist < EPSILON)
                    return 0.0;
                depth += dist;
            }
        }
    }

    // Nothing is in the path of the lightray and therefore no shadow is needed
    // TODO Adjust such that the smallest distance is returned (soft shadow)
    return light_dist;
}

float inShadow(vec3 collision, vec3 light_pos, vec3 normal, float planeDist) {
    // Dont forget to normalize!
    vec3 light_dir = normalize(light_pos - collision);
    float light_dist = length(light_pos - collision);

    // If we are at the backside then we are in the shadow
    if (max(dot(light_dir, normal), 0.0) == 0.0)
        return 1.0;

    float dist = shadowRaymarching(
        collision - normal * EPSILON,
        light_dir,
        planeDist,
        light_pos
    );

     // Not in shadow
    if (dist >= light_dist - EPSILON)
		return 0.0;
    // In shadow
    else
        return 1.0;

}

///////////////////////////////////////////////////////////////////////////////
// Background
///////////////////////////////////////////////////////////////////////////////
void drawBackground(vec3 camera, vec3 dir, vec3 light_pos, float planeDist)
{
    const vec2 h = vec2(EPSILON, 0.0);

    float dist = MAX_DIST;
    float depth = EPSILON;
    vec3 pos = vec3(0.0, 0.0, planeDist - 10.0);

    for (int i = 0; i < 400 && depth < MAX_DIST; i++)
    {
        dist = effectSDF(camera + dir * depth, pos);
        if (dist < EPSILON)
        {
            vec3 point = camera + dir * depth;
            vec3 snorm = normalize(
                vec3(effectSDF(point+h.xyy, pos) - effectSDF(point-h.xyy, pos),
                     effectSDF(point+h.yxy, pos) - effectSDF(point-h.yxy, pos),
                     effectSDF(point+h.yyx, pos) - effectSDF(point-h.yyx, pos))
            );

            oColor.rgb = vec3(0.1) * (phong_ambient + phongOfPoint(
                light_pos, camera, point, snorm
            ));
            oColor.a = 1.0;
            return;
        }
        depth += dist;
    }
    float alpha = length(gl_FragCoord.xy / uResolution - vec2(0.5)) - 0.05;
    oColor = vec4(vec3(0.1), alpha);
}

///////////////////////////////////////////////////////////////////////////////
// Reflections
///////////////////////////////////////////////////////////////////////////////
float reflectionRaymarching(vec3 camera, vec3 ray, float planeDist)
{
    vec2 dir = ray.xy;
	vec2 start = camera.xy;
    vec2 end = camera.xy + dir * 3.0;

    // Run a bresenham algorithm to iterate all stones on the path of the ray
    vec2 step = sign(dir);
    dir = abs(dir);

    // If distance to small adjust it to avoid division by 0
    // This is done componentwise to allow for axis aligned vectors (e.g. 1,0)
    if (dir.x <= EPSILON)
        dir.x = EPSILON;
    if (dir.y <= EPSILON)
        dir.y = EPSILON;

    if (round(start.x - end.x) == 0.0 && round(start.y - end.y) == 0.0)
        return MAX_DIST;

    // Calculate the distance from the start point
    // to the edges of a stonefield which could intersect the ray
    // This is dependend on the ray direction.
    vec2 tMax = fract(start);
    if (step.x > 0.0)
        tMax.x = BOX_DIMS.x - tMax.x;
    if (step.y > 0.0)
        tMax.y = BOX_DIMS.y - tMax.y;
    tMax /= dir;

        //debugVec.xy = tMax;


    // Calculate the offset by which the point is moved to reach the next stonepos
    vec2 tDelta = BOX_DIMS.xy / dir;

    // As long as the stepcount is not exceeded and the lightpos is not reached continue
    for (int steps = 0; (start.x * step.x < end.x * step.x || start.y * step.y < end.y * step.y) &&
         steps < REFLECTION_ITER_COUNT; steps++)
    {
        // Advance the start position, this depends on the slope of the dirVec (lower first)
        // Increase the tDelta to switch direction as soon as necessary
        if (tMax.x < tMax.y)
        {
            tMax.x += tDelta.x;
            start.x += step.x;
        }
        else
        {
            tMax.y += tDelta.y;
            start.y += step.y;
        }

        // Use the position to calculate the texture coords
        // these need to be adjusted to be only positive
        ivec2 uv = ivec2(floor(start) + dimsHalf);

        float material = texelFetch(uBoardTex, uv, 0).x;
        // If the position is occupied check whether the ray actually hits this stone
        if (material > 0.0)
    	{
        	//vec3 newPos = vec3(floor(start) + vec2(0.5), planeDist);

            float depth = 0.0;
            float dist = MAX_DIST;

            // TODO max(boxdims) instead of lightdist?
            for (int i = 0; i < MAX_SHADOW_MARCHING_STEPS && depth < MAX_DIST; i++)
            {
             	dist = min(dist, drawField(
                    camera + depth * ray, start, material, planeDist, dist
                ));
                // If the distance is small then the stone was hit
                // otherwise continue following the ray
                if (dist < EPSILON)
                    return 0.0;
                depth += dist;
            }
        }
    }

    // Nothing is in the path of the lightray and therefore no shadow is needed
    // TODO Adjust such that the smallest distance is returned (soft shadow)
    return MAX_DIST;
}

vec3 getReflection(vec3 camera, vec3 dir, vec3 normal, float planeDist)
{
    vec3 reflDir = reflect(dir, normal);

    float dist = reflectionRaymarching(camera + EPSILON * reflDir, reflDir, planeDist);
    if (dist >= MAX_DIST)
    {
    	return vec3(0.0);
    }
                //debugVec.z = 1.0;

    return materials[l_hit.mat_id].color;
    //return reflDir;
}

///////////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////////
void main()
{
    dimsHalf = vec2(uWidth / 2.0, uHeight / 2.0);

    materials[0] = material(rainbowColor(0.8, 0.1), 0.0);

    l_hit = hit(vec3(0.0), 0, vec3(0.0), vec3(0.0));
    vec3 camera = uCameraPos;
    float fieldOfView = 45.0;
    vec3 dir = rayDirection(fieldOfView, gl_FragCoord.xy);

    float which = uResolution.x / uWidth < uResolution.y / uHeight ?
        uWidth : uHeight;
    float planeDist = -(which + 3.0) / tan(radians(fieldOfView) * 0.5);

    vec3 light_pos = vec3(
        sin(uTime) * dimsHalf.x,
        cos(uTime) * dimsHalf.y,
        planeDist + abs(sin(uTime * 0.75)) * 1.25 + 0.75
    );

    float dist = boundRaymarching(camera, dir, planeDist);
    if (dist >= MAX_DIST)
    {
		drawBackground(camera, dir, light_pos, planeDist);
        return;
    }

    vec3 colors[2];
    vec3 normals[2];
    float shadowVals[2];
    vec3 lightVals[2];
    normals[0] = estimateNormal(l_hit.hit_p, l_hit.obj_center, l_hit.mat_id);
    shadowVals[0] = inShadow(l_hit.hit_p, light_pos, normals[0], planeDist);

    lightVals[0] += phong_ambient + (1.0 - shadowVals[0]) * phongOfPoint(
        light_pos,
        camera, l_hit.hit_p, normals[0]
    );

    colors[0] = materials[l_hit.mat_id].color;

    float refl = materials[l_hit.mat_id].reflection;
    colors[1] = getReflection(l_hit.hit_p, dir, normals[0], planeDist);

    normals[1] = estimateNormal(l_hit.hit_p, l_hit.obj_center, l_hit.mat_id);
    shadowVals[1] = inShadow(l_hit.hit_p, light_pos, normals[1], planeDist);

    lightVals[1] = phong_ambient + (1.0 - shadowVals[1]) * phongOfPoint(
        light_pos,
        camera, l_hit.hit_p, normals[1]
    );

    oColor = vec4(1.0);
    oColor.rgb = (1.0 - refl) * colors[0];
    oColor.rgb += refl * colors[1] * lightVals[1];

    oColor.rgb *= lightVals[0];

#if DEBUG == 1
    oColor.rgb = l_hit.hit_p;
#elif DEBUG == 2
    oColor.rgb = normal;
#elif DEBUG == 3
    oColor.rgb = materials[l_hit.mat_id].color;
#elif DEBUG == 4
    oColor.rgb = vec3(sVal);
#elif DEBUG == 5
    oColor.rgb = debugVec;
#endif
}
