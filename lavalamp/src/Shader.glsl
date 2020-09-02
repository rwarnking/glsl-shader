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

///////////////////////////////////////////////////////////////////////////////////////////////////
// Defines
///////////////////////////////////////////////////////////////////////////////////////////////////
#define phong_ambient vec3(0.2)
#define phong_diffuse vec3(1.0)
#define phong_specular vec3(1.0)
#define phong_shine 32.0

#define STAND_COLOR vec3(0.5, 0.5, 1.0)

// Object information
// 0 => Sphere, 1 => Cube, 2 => Cone
#define OBJECT 0
#define OUTSIDE_MAT 1.0
#define INSIDE_MAT 1.0
#define BALL_COUNT 5

// Layer information
#define LAYER_COUNT 4
#define FRONT_OUT_LAYER 0
#define FRONT_IN_LAYER 1
#define BACK_IN_LAYER 2
#define BACK_OUT_LAYER 3
#define DEBUG_OUT 4

#define DEBUG -1

#if DEBUG == DEBUG_OUT
vec3 debugVec = vec3(0.0);
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
// Uniforms
///////////////////////////////////////////////////////////////////////////////////////////////////
uniform vec2 uResolution;
uniform float uTime;

uniform vec3 uCameraPos;
uniform mat4 uLookAt;

uniform float uContainerRefrIdx;
uniform vec3 uContainerSize;
uniform vec4 uLavaInfo[BALL_COUNT];

uniform samplerCube uEnvirCube;

out vec4 out_fragColor;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Constant Variables
///////////////////////////////////////////////////////////////////////////////////////////////////
const int MAX_MARCHING_STEPS = 255;
const float MAX_DIST = 100.0;
const float EPSILON = 0.001;

const vec3 lavaColor = vec3(1.0, 0.0, 0.0);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Structs
///////////////////////////////////////////////////////////////////////////////////////////////////
struct hit {
    vec3 obj_center;
    vec3 hit_p;
    vec3 dim;
    int id;
} l_hit;

struct container {
    vec3 pos;
    vec3 dims;
    vec3 color;
    float glassThickness;
    float refrAmount;
    float refrIndex;
} g_c;

struct layer {
	vec3 color;
    vec3 normal;
    float reflAmount;
};

layer layers[LAYER_COUNT] = layer[](
    layer(vec3(0.0), vec3(0.0), 0.0),
    layer(vec3(0.0), vec3(0.0), 0.0),
    layer(vec3(0.0), vec3(0.0), 0.0),
    layer(vec3(0.0), vec3(0.0), 0.0)
);

///////////////////////////////////////////////////////////////////////////////////////////////////
// Helper Functions
///////////////////////////////////////////////////////////////////////////////////////////////////
/**
 * Normalized direction to march from the eye point for a single pixel.
 *
 * @param fieldOfView vertical field of view in degrees
 * @param fragCoord the x,y coordinate of the pixel in the output image
 */
vec3 rayDirection(float fieldOfView, vec2 fragCoord)
{
    vec2 xy = fragCoord - uResolution * 0.5;
    float z = uResolution.y / tan(radians(fieldOfView) * 0.5);
    return normalize(vec3(xy, -z));
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Signed Distance Functions
///////////////////////////////////////////////////////////////////////////////////////////////////
float sphereSDF(vec3 samplePoint, float s)
{
	return length(samplePoint) - s;
}

float sphereSDF(vec3 samplePoint, vec3 pos, float s)
{
	return length(samplePoint - pos) - s;
}

// float sphereSDF2(vec3 samplePoint, vec3 pos, float s)
// {
// 	return s / length(samplePoint - pos);
// }

float boxSDF(vec3 samplePoint, vec3 d)
{
	vec3 q = abs(samplePoint) - d;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float boxSDF(vec3 samplePoint, vec3 pos, vec3 d)
{
	vec3 q = abs(samplePoint - pos) - d;
	return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float cappedConeSDF(vec3 p, vec3 pos, float h, float r1, float r2)
{
    vec2 q = vec2( length(p.xz - pos.xz), p.y - pos.y);
    vec2 k1 = vec2(r2,h);
    vec2 k2 = vec2(r2-r1,2.0*h);
    vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
    vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot(k2, k2), 0.0, 1.0 );
    float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
    return s*sqrt( min(dot(ca, ca),dot(cb, cb)) );
}

float roundConeSDF(vec3 samplePoint, vec3 d)
{
    // TODO y shift 1.5 does not work always
    vec2 q = vec2(length(samplePoint.xz), samplePoint.y + d.y * 1.5);

    float b = (d.x - d.y) / d.z;
    float a = sqrt(1.0 - b * b);
    float k = dot(q, vec2(-b, a));

    if (k < 0.0) 
        return length(q) - d.x;
    if (k > a * d.z) 
        return length(q - vec2(0.0, d.z)) - d.y;

    return dot(q, vec2(a, b)) - d.x;
}

float metaballSDF(vec3 samplePoint)
{
    float sum = 0.0;
    for (int i = 0; i < uLavaInfo.length(); i++)
    {
        float r = dot(samplePoint - uLavaInfo[i].xyz, samplePoint - uLavaInfo[i].xyz);
        sum = sum + min(1.0 / r * uLavaInfo[i].w, 1.0);
    }
    float R = 0.5;
    return R - sum;
}

// https://www.scratchapixel.com/lessons/advanced-rendering/rendering-distance-fields/blobbies
// float metaballSDF2(vec3 samplePoint)
// {
//     float sumDensity = 0.0; 
//     float sumRi = 0.0; 
//     float minDistance = MAX_DIST; 
    
//     float magic = 0.2;
    
//     for (int i = 0; i < uLavaInfo.length(); i++) 
//     {
//         float r = length(uLavaInfo[i].xyz - samplePoint); 
//         if (r <= uLavaInfo[i].w) 
//         { 
//             // this can be factored for speed if you want
//             float R = uLavaInfo[i].w;
//             sumDensity += 2.0 * (r * r * r) / (R * R * R) - 
//                 3.0 * (r * r) / (R * R) + 1.0; 
//         } 
//         minDistance = min(minDistance, r - uLavaInfo[i].w); 
//         sumRi += uLavaInfo[i].w; 
//     } 

//     return max(minDistance, (magic - sumDensity) / ( 3.0 / 2.0 * sumRi)); 
// }

float containerSDFOutside(vec3 samplePoint)
{
#if OBJECT == 0
    return sphereSDF(samplePoint, g_c.dims.x);
#elif OBJECT == 1
    return boxSDF(samplePoint, g_c.dims);
#else 
    return roundConeSDF(samplePoint, g_c.dims);
#endif
}

float containerSDFInside(vec3 samplePoint)
{
#if OBJECT == 0
    return sphereSDF(samplePoint, g_c.dims.x - g_c.glassThickness);
#elif OBJECT == 1
    return boxSDF(samplePoint, g_c.dims - g_c.glassThickness);
#else 
    return roundConeSDF(samplePoint, g_c.dims - g_c.glassThickness);
#endif
}

float standSDF(vec3 samplePoint)
{
    float height = 1.0;
    vec2 r1r2 = vec2(3.0, 2.0);
    vec3 pos = vec3(0.0, -uContainerSize.y - height + 0.4, 0.0);
#if OBJECT == 0
    return cappedConeSDF(samplePoint, pos, height, r1r2.x, r1r2.y);
#elif OBJECT == 1
    return boxSDF(samplePoint, g_c.dims - g_c.glassThickness);
#else 
    return roundConeSDF(samplePoint, g_c.dims - g_c.glassThickness);
#endif
}

float sceneSDF(vec3 samplePoint)
{
    return containerSDFOutside(samplePoint);
}

float sceneSDF2(vec3 samplePoint)
{
    return containerSDFInside(samplePoint);
}

float sceneSDFOutside(vec3 samplePoint)
{
    float distStand = standSDF(samplePoint);
    float distContainer = containerSDFOutside(samplePoint);
    if (distStand < distContainer)
    {
        l_hit.id = 2;
        return distStand;
    }
    else 
    {
        l_hit.id = 1;
        return distContainer;
    }
}

float sceneSDFOutside2(vec3 samplePoint)
{
	return standSDF(samplePoint);
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Draw Parts
///////////////////////////////////////////////////////////////////////////////////////////////////
float raymarching(vec3 camera, vec3 ray)
{    
    float depth = 0.0;
    float dist = MAX_DIST;
    for (int i = 0; i < MAX_MARCHING_STEPS && depth < MAX_DIST; i++)
    {
        dist = sceneSDFOutside(camera + depth * ray);        
        if (dist < EPSILON) 
        {
            l_hit.hit_p = camera + depth * ray;
            
            return depth;
        }
        depth += dist;
    }
    
    return MAX_DIST;
}

float raymarching2(vec3 camera, vec3 ray)
{    
    float depth = 0.0;
    float dist = MAX_DIST;
    for (int i = 0; i < MAX_MARCHING_STEPS && depth < MAX_DIST; i++)
    {
        dist = sceneSDFOutside2(camera + depth * ray);        
        if (dist < EPSILON) 
        {
            l_hit.hit_p = camera + depth * ray;
            
            return dist;
        }
        depth += dist;
    }
    
    return MAX_DIST;
}

float raymarchGlass(vec3 origin, vec3 ray)
{       
    float depth = 0.0;
    float dist = MAX_DIST;
    for (int i = 0; i < MAX_MARCHING_STEPS && depth < MAX_DIST; i++)
    {
        vec3 pos = origin + depth * ray;
        l_hit.hit_p = pos;
        
        float distOut = containerSDFOutside(pos);
        if (distOut > 0.0)
        {
            // TODO do a loop here till in EPSILON range?
            // TODO this slows it down hard
            for (int i = 0; i < MAX_MARCHING_STEPS / 15 && distOut > 0.0; i++)
            {
            	l_hit.hit_p -= distOut * ray;
            	distOut = containerSDFOutside(l_hit.hit_p);
            }
            
            return MAX_DIST;
        }

        dist = containerSDFInside(pos);
        if (dist < EPSILON)
        {
            // TODO do a loop here till in EPSILON range?
            // TODO this slows it down hard
            for (int i = 0; i < MAX_MARCHING_STEPS / 15 && dist < 0.0; i++)
            {
            	l_hit.hit_p -= max(-dist, EPSILON) * ray;
            	dist = containerSDFInside(l_hit.hit_p);
            }
            
            return 0.0;
        }
        // TODO Improve this
        // Since we need to find the point at which the object is left 
        // a fixed stepsize is necessary. This stepsize should depend
        // on the maxmimum distance a ray could have divided by the maximum 
        // amount of steps that are allowed.
        float maxDim = max(g_c.dims.x, max(g_c.dims.y, g_c.dims.z));
        float maxLen = maxDim * maxDim + maxDim * maxDim;
        depth += maxLen / float(MAX_MARCHING_STEPS);
        //depth += min(dist, -distOut);
    }
    
    return MAX_DIST;
}

float raymarchInside(vec3 origin, vec3 ray)
{       
    float depth = 0.0;
    float dist = MAX_DIST;
    for (int i = 0; i < MAX_MARCHING_STEPS && depth < MAX_DIST; i++)
    {
        l_hit.hit_p = origin + depth * ray;
        dist = metaballSDF(l_hit.hit_p);
        if (dist < EPSILON)
        {
            return 0.0;
        }
        dist = min(dist, boxSDF(l_hit.hit_p, vec3(0.0, -g_c.dims[1] + 0.25, 0.0), vec3(1.0, 0.0, 1.0)));
        if (dist < EPSILON)
        {
            return -1.0;
        }

        float distOut = containerSDFOutside(l_hit.hit_p);
        if (distOut > 0.0)
        {
            // TODO do a loop here till in EPSILON range?
            // TODO this slows it down hard
            for (int i = 0; i < MAX_MARCHING_STEPS / 15 && distOut > EPSILON; i++)
            {
            	l_hit.hit_p -= max(distOut, EPSILON * 10.0) * ray;
            	distOut = containerSDFOutside(l_hit.hit_p);
            }
            return MAX_DIST;
        }
        depth += dist;
    }
    
    return MAX_DIST;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Lighting
///////////////////////////////////////////////////////////////////////////////////////////////////
vec3 containerNormalOutside(vec3 p)
{
    if (l_hit.id == 2)
    {
        return normalize(vec3(
            standSDF(vec3(p.x + EPSILON, p.y, p.z)) -
            standSDF(vec3(p.x - EPSILON, p.y, p.z)),
            standSDF(vec3(p.x, p.y + EPSILON, p.z)) -
            standSDF(vec3(p.x, p.y - EPSILON, p.z)),
            standSDF(vec3(p.x, p.y, p.z + EPSILON)) -
            standSDF(vec3(p.x, p.y, p.z - EPSILON))
        ));
    }
    else
    {
        return normalize(vec3(
            containerSDFOutside(vec3(p.x + EPSILON, p.y, p.z)) -
            containerSDFOutside(vec3(p.x - EPSILON, p.y, p.z)),
            containerSDFOutside(vec3(p.x, p.y + EPSILON, p.z)) -
            containerSDFOutside(vec3(p.x, p.y - EPSILON, p.z)),
            containerSDFOutside(vec3(p.x, p.y, p.z + EPSILON)) -
            containerSDFOutside(vec3(p.x, p.y, p.z - EPSILON))
        ));
    }
}

vec3 containerNormalInside(vec3 p)
{
    return normalize(vec3(
        containerSDFInside(vec3(p.x + EPSILON, p.y, p.z)) -
        containerSDFInside(vec3(p.x - EPSILON, p.y, p.z)),
        containerSDFInside(vec3(p.x, p.y + EPSILON, p.z)) -
        containerSDFInside(vec3(p.x, p.y - EPSILON, p.z)),
        containerSDFInside(vec3(p.x, p.y, p.z + EPSILON)) -
        containerSDFInside(vec3(p.x, p.y, p.z - EPSILON))
    ));
}

vec3 estimateMetaballNormal(vec3 p)
{
    return normalize(vec3(
        metaballSDF(vec3(p.x + EPSILON, p.y, p.z)) -
        metaballSDF(vec3(p.x - EPSILON, p.y, p.z)),
        metaballSDF(vec3(p.x, p.y + EPSILON, p.z)) -
        metaballSDF(vec3(p.x, p.y - EPSILON, p.z)),
        metaballSDF(vec3(p.x, p.y, p.z + EPSILON)) -
        metaballSDF(vec3(p.x, p.y, p.z - EPSILON))
    ));
}
    
vec3 phongOfPointOutside(vec3 cam_pos, vec3 hit_point, vec3 normal)
{
    vec3 light_pos = vec3(0.0);
    vec3 light_dir = normalize(light_pos - hit_point);
    vec3 view_dir = normalize(cam_pos - hit_point);
    
    float light_intensity = max(dot(normal, light_dir), 0.0);

    if (light_intensity > 0.0)
    {
        vec3 diffuse = light_intensity * phong_diffuse;

        float specular_strength = 1.0;
        vec3 reflect_dir = reflect(-light_dir, normal);

        float spec = pow(max(dot(view_dir, reflect_dir), 0.0), phong_shine);
        vec3 specular = specular_strength * spec * phong_specular;

        return diffuse + specular;
    }
	return vec3(0.0);
}

float attenuation(vec3 toLight)
{
    float d = length(toLight) / 5.0;
    return 1.0 / (1.0 + 1.0 * d + 1.0 * d * d);
}

vec3 phongOfPointInside(vec3 cam_pos, vec3 hit_point, vec3 normal)
{
    // vec3 light_pos = vec3(sin(uTime), cos(uTime), 0.0) * g_c.dims * 20.0;
    vec3 light_pos = vec3(0.0, -g_c.dims.y, 0.0);
    vec3 light_dir = normalize(light_pos - hit_point);
    vec3 view_dir = normalize(cam_pos - hit_point);
    
    vec3 tmp = vec3(-1.0, -g_c.dims.y, 1.0);
    vec3 light_dir1 = normalize(tmp - hit_point);
    vec3 light_dir2 = normalize(tmp.zyx - hit_point);
    vec3 light_dir3 = normalize(tmp.xyz - hit_point);    
    vec3 light_dir4 = normalize(tmp.xyx - hit_point);

    // float light_intensity = max(dot(normal, light_dir), 0.0);
    float len = abs(light_pos.y - hit_point.y);
    float light_intensity = (
        max(dot(normal, light_dir1), 0.0) +
        max(dot(normal, light_dir2), 0.0) +
        max(dot(normal, light_dir3), 0.0) +
        max(dot(normal, light_dir4), 0.0)
    ) / 4.0;

    // TODO should there be a specular light ?
    // vec3 diffuse = light_intensity * phong_diffuse;
    // float specular_strength = 1.0;
    // vec3 reflect_dir = reflect(-light_dir, normal);
    // float spec = pow(max(dot(view_dir, reflect_dir), 0.0), phong_shine);
    // vec3 specular = specular_strength * spec * phong_specular;

    // TODO refactor
    float SSSAmbient     = 1.0;
    float SSSDistortion  = 1.0;
    float SSSPower       = 1.0;
    float SSSScale       = 1.0;

    vec3  toLight     = light_pos - hit_point;
    float attenuation = attenuation(toLight);
    vec3  toEye    = -view_dir;
    vec3  SSSLight = (normalize(light_pos - hit_point) + normal * SSSDistortion);
    float SSSDot   = pow(clamp(dot(toEye, -SSSLight), 0.0, 1.0), SSSPower) * SSSScale;
    float SSS      = (SSSDot + SSSAmbient) * attenuation;

    vec3 color = phong_diffuse * (SSS + light_intensity);

    return color;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Raymarch Layers
///////////////////////////////////////////////////////////////////////////////////////////////////

// TODO Apply the color of the container
vec3 evaluateOutside(vec3 origin, vec3 dir) 
{
    float dist = raymarching(origin, dir);
    // If the main object is not hit, render the environment
    // TODO how much longer can it be? (EPSILON * 10.0)
    vec3 pos = origin + (dist + EPSILON * 10.0) * dir;
    float res = sceneSDFOutside(pos);
    if (res >= 0.0)
    {
        layers[FRONT_OUT_LAYER].color = texture(uEnvirCube, vec3(dir)).rgb;
    	layers[FRONT_OUT_LAYER].reflAmount = 1.0;
        return pos;
    }
    
    // TODO calculate lighting
    // TODO ave lhit.hit_p in the layer so the light can be calculated afterwards?
    // Since the object is transparent this is not that easy
    //vec3 containerPhong = max(phong_ambient, phongOfPoint(
    //    light_pos, camera, l_hit.hit_p, normal
    //));
    
    vec3 normal = containerNormalOutside(l_hit.hit_p);
    vec3 reflDir = reflect(dir, normal);
    
    if (l_hit.id == 2)
    {
        vec3 objLight = max(phong_ambient, phongOfPointOutside(origin, l_hit.hit_p, normal));
        
        // float t = 0.85;
        // layers[FRONT_OUT_LAYER].color = 
        //     (vec3(1.0) * t + texture(uEnvirCube, vec3(reflDir)).rgb * (1.0 - t)) * objLight;
        layers[FRONT_OUT_LAYER].color = STAND_COLOR * objLight;
        layers[FRONT_OUT_LAYER].reflAmount = 1.0;
    }
    else
    {
        layers[FRONT_OUT_LAYER].color = texture(uEnvirCube, vec3(reflDir)).rgb;
        vec3 light_pos = vec3(0.0, -g_c.dims.y, 0.0);
        layers[FRONT_OUT_LAYER].reflAmount = 1.0 - dot(normal, -dir) * dot(normal, -dir);
    }
    layers[FRONT_OUT_LAYER].normal = normal;
    
    return pos;
}

vec3 evaluateGlassLayer(vec3 origin, vec3 dir)
{
    // Refract the ray
    vec3 normal = layers[FRONT_OUT_LAYER].normal;
    float k = 0.0;
    float eta = OUTSIDE_MAT / g_c.refrIndex;
    vec3 refrRay = normalize(refract(dir, normal, eta));
    //pos = l_hit.hit_p + (EPSILON * 10.0) * dir;
    
    // If the ray enteres the glass and leaves it without 
    // intersecting the inner part render a refracted background
	float res = raymarchGlass(origin, refrRay);
    if (res > EPSILON)
    {
    	normal = -containerNormalOutside(l_hit.hit_p);
        eta = g_c.refrIndex / OUTSIDE_MAT;
        // Check for Total Internal Reflection
        k = 1.0 - eta * eta * 
            (1.0 - dot(normal, refrRay) * dot(normal, refrRay));
        
        // TODO this does not happen
        if (k > 0.0)
        {
    		refrRay = normalize(refract(refrRay, normal, eta));
            layers[FRONT_IN_LAYER].color = texture(uEnvirCube, vec3(refrRay)).rgb;
            layers[FRONT_IN_LAYER].reflAmount = 1.0;
            layers[FRONT_IN_LAYER].normal = normal;
        }
        else
        {
            layers[FRONT_IN_LAYER].color = vec3(0.0, 1.0, 0.0);
            layers[FRONT_IN_LAYER].reflAmount = 1.0;
            layers[FRONT_IN_LAYER].normal = normal;
        }

        return refrRay;
    }
    
    // Inner sphere was hit, calculate new refraction vector
    normal = containerNormalInside(l_hit.hit_p);
    
    // TODO add correct reflection
    vec3 reflDir = reflect(refrRay, normal);
    layers[FRONT_IN_LAYER].color = texture(uEnvirCube, vec3(reflDir)).rgb;
    layers[FRONT_IN_LAYER].normal = normal;
    
    // Check for Total Internal Reflection
    eta = g_c.refrIndex / INSIDE_MAT;
    k = 1.0 - eta * eta * 
        (1.0 - dot(normal, refrRay) * dot(normal, refrRay));
    if (k < 0.0)
    {
        layers[FRONT_IN_LAYER].reflAmount = 1.0;

        return refrRay;
    }
    else
    {
    	layers[FRONT_IN_LAYER].reflAmount = 1.0 - dot(normal, refrRay) * dot(normal, refrRay);
    }
    
    refrRay = normalize(refract(refrRay, normal, eta));
    return refrRay;
}

void evaluateInside(vec3 origin, vec3 dir)
{                        
    // If the ray inside does hit one of the objects inside render these
    float res = raymarchInside(l_hit.hit_p, dir);
    
    if (res < 0.0)
    {
        //vec3 objNormal = estimateMetaballNormal(l_hit.hit_p);
        //vec3 objLight = max(phong_ambient, phongOfPointInside(origin, l_hit.hit_p, objNormal));
        
        layers[BACK_IN_LAYER].color = vec3(1.0, 0.945, 0.878);
        layers[BACK_IN_LAYER].reflAmount = 1.0;
        layers[BACK_IN_LAYER].normal = vec3(0.0, 1.0, 0.0);
    }
    else if (res < EPSILON)
    {
        vec3 objNormal = estimateMetaballNormal(l_hit.hit_p);
        vec3 objLight = max(phong_ambient, phongOfPointInside(origin, l_hit.hit_p, objNormal));
        
        layers[BACK_IN_LAYER].color = lavaColor * objLight;
        layers[BACK_IN_LAYER].reflAmount = 1.0;
        layers[BACK_IN_LAYER].normal = objNormal;
    }
    else 
    {
        layers[BACK_IN_LAYER].color = vec3(0.0);
        layers[BACK_IN_LAYER].reflAmount = 0.0;
        layers[BACK_IN_LAYER].normal = vec3(0.0);
    }
}

void evaluateBackside(vec3 dir)
{
    // If no object was hit inside the object, traverse the container and 
    // get the refracted background
    vec3 normal = -containerNormalInside(l_hit.hit_p);
    
    float eta = INSIDE_MAT / g_c.refrIndex;
    vec3 refrRay = normalize(refract(dir, normal, eta));

    float res = raymarchGlass(l_hit.hit_p, refrRay);
    if (res > MAX_DIST - EPSILON)
    {
        normal = -containerNormalOutside(l_hit.hit_p);
        
        eta = g_c.refrIndex / OUTSIDE_MAT;
        // Check for Total Internal Reflection
        float k = 1.0 - eta * eta * 
            (1.0 - dot(normal, refrRay) * dot(normal, refrRay));
        
        if (k > 0.0)
        {
    		refrRay = normalize(refract(refrRay, normal, eta));
            float dist = raymarching2(l_hit.hit_p, refrRay);
 			// TODO own method?
            if (dist < EPSILON)
            {
                l_hit.id = 2;
                
                normal = containerNormalOutside(l_hit.hit_p);
                vec3 objLight = max(phong_ambient, phongOfPointOutside(
                    uCameraPos, l_hit.hit_p, normal
                ));

                // float t = 0.85;
                // layers[FRONT_OUT_LAYER].color = 
                //     (vec3(1.0) * t + texture(uEnvirCube, vec3(reflDir)).rgb * (1.0 - t)) * objLight;
                layers[BACK_OUT_LAYER].color = STAND_COLOR * objLight;
                layers[BACK_OUT_LAYER].reflAmount = 1.0;
                layers[BACK_OUT_LAYER].normal = normal;
                return;
            }
            
            
            // TODO smthg is still wrong here
            layers[BACK_OUT_LAYER].color = texture(uEnvirCube, vec3(refrRay)).rgb;
            layers[BACK_OUT_LAYER].reflAmount = 1.0;
            layers[BACK_OUT_LAYER].normal = normal;
        }
        else 
        {
            layers[BACK_OUT_LAYER].color = vec3(1.0, 0.0, 0.0);
            layers[BACK_OUT_LAYER].reflAmount = 1.0;
            layers[BACK_OUT_LAYER].normal = normal;
        }
        
        return;
    }

    layers[BACK_OUT_LAYER].color = vec3(0.0, 0.0, 1.0);
    layers[BACK_OUT_LAYER].reflAmount = 1.0;
    layers[BACK_OUT_LAYER].normal = normal;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Main
///////////////////////////////////////////////////////////////////////////////////////////////////
void main()
{
    l_hit = hit(vec3(0.0), vec3(0.0), vec3(0.0), 0);
    g_c = container(vec3(0.0), uContainerSize, vec3(1.0), 0.3, 0.1, uContainerRefrIdx);
    out_fragColor = vec4(0.0, 0.0, 0.0, 1.0);
    
    vec3 camera = uCameraPos;
    float fieldOfView = 45.0;
    vec3 dir = rayDirection(fieldOfView, gl_FragCoord.xy);
    
    dir = (uLookAt * vec4(dir, 0.0)).xyz;
    
    // TODO improve this such that the functions are not executed 
    // when not necessary
	vec3 origin = evaluateOutside(camera, dir);
    dir = evaluateGlassLayer(origin, dir);
    evaluateInside(origin, dir);
    evaluateBackside(dir);

#if DEBUG == FRONT_IN_LAYER
    out_fragColor.rgb = layers[FRONT_IN_LAYER].color;
#elif DEBUG == FRONT_OUT_LAYER
    out_fragColor.rgb = layers[FRONT_OUT_LAYER].color;
#elif DEBUG == BACK_IN_LAYER
    out_fragColor.rgb = layers[BACK_IN_LAYER].color;
#elif DEBUG == BACK_OUT_LAYER
    out_fragColor.rgb = layers[BACK_OUT_LAYER].color;
#elif DEBUG == DEBUG_OUT
    out_fragColor.rgb = debugVec;
#else 
    for (int i = LAYER_COUNT - 1; i >= 0; i--)
    {
        out_fragColor.rgb = out_fragColor.rgb * (1.0 - layers[i].reflAmount) +  
            layers[i].color * layers[i].reflAmount;
    }
#endif
}