#include <CoreImage/CoreImage.h>
using namespace metal;

static float bayer(uint2 cell, uint bits) {
    uint rank = 0;
    for (uint bit = 0; bit < bits; ++bit) {
        uint x = (cell.x >> bit) & 1, y = (cell.y >> bit) & 1;
        rank = 4 * rank + 2 * (x ^ y) + y;
    }
    return (float(rank) + 0.5f) / float(1u << (2u * bits));
}

static float stipple(uint2 cell) {
    uint hash = (cell.x * 1597334677u) ^ (cell.y * 3812015801u);
    hash = (hash ^ (hash >> 16)) * 2246822519u;
    return float(hash >> 8) / 16777216.0f;
}

extern "C" {
namespace coreimage {
    float4 dither(sample_t sample, float method, float strength, float levels,
                  float mode, float4 a, float4 b, float4 c, float4 d,
                  destination dest) {
        float4 source = unpremultiply(sample);
        uint2 cell = uint2(dest.coord());
        uint algorithm = uint(method);
        float threshold = 0.5f;
        if (algorithm > 0 && algorithm < 4) threshold = bayer(cell, algorithm);
        if (algorithm == 4) threshold = stipple(cell);
        float offset = (0.5f - threshold) * strength;
        float3 input = clamp(source.rgb, 0.0f, 1.0f);
        float luma = dot(input, float3(0.2126f, 0.7152f, 0.0722f));
        float3 result;
        if (mode == 1) {
            result = clamp(floor(input * levels + 0.5f + offset), 0.0f, levels) / levels;
        } else {
            float index = clamp(floor(luma * levels + 0.5f + offset), 0.0f, levels);
            if (mode == 0) result = float3(index / levels);
            else result = index == 0 ? a.rgb : index == 1 ? b.rgb : index == 2 ? c.rgb : d.rgb;
        }
        return premultiply(float4(result, source.a));
    }
}
}
