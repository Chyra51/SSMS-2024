Shader "Hidden/SSMS Global Fog" Updated
{
    Properties
    {
        _MainTex("Base (RGB)", 2D) = "black" {}
    }

    CGINCLUDE

    #include "UnityCG.cginc"

    uniform sampler2D _MainTex;
    uniform sampler2D_float _CameraDepthTexture;

    uniform float4 _HeightParams;
    uniform float4 _DistanceParams;

    int4 _SceneFogMode;
    float4 _SceneFogParams;

    #ifndef UNITY_APPLY_FOG
    half4 unity_FogColor;
    half4 unity_FogDensity;
    #endif    

    uniform float4 _MainTex_TexelSize;
    uniform float4x4 _FrustumCornersWS;
    uniform float4 _CameraWS;

    uniform float _MaxValue;
    uniform half4 _FogTint;
    uniform half _EnLoss;

    struct appdata_fog
    {
        float4 vertex : POSITION;
        half2 texcoord : TEXCOORD0;
    };

    struct v2f
    {
        float4 pos : SV_POSITION;
        float2 uv : TEXCOORD0;
        float2 uv_depth : TEXCOORD1;
        float4 interpolatedRay : TEXCOORD2;
    };

    v2f vert(appdata_fog v)
    {
        v2f o;
        v.vertex.z = 0.1;
        o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
        o.uv = v.texcoord.xy;
        o.uv_depth = v.texcoord.xy;

        #if UNITY_UV_STARTS_AT_TOP
        if (_MainTex_TexelSize.y < 0)
            o.uv.y = 1 - o.uv.y;
        #endif                

        int frustumIndex = v.texcoord.x + (2 * o.uv.y);
        o.interpolatedRay = _FrustumCornersWS[frustumIndex];
        o.interpolatedRay.w = frustumIndex;

        return o;
    }

    half ComputeFogFactor(float coord)
    {
        float fogFac = 0.0;
        if (_SceneFogMode.x == 1) // linear
        {
            fogFac = coord * _SceneFogParams.z + _SceneFogParams.w;
        }
        else if (_SceneFogMode.x == 2) // exp
        {
            fogFac = exp2(-_SceneFogParams.y * coord);
        }
        else if (_SceneFogMode.x == 3) // exp2
        {
            fogFac = exp2(-(_SceneFogParams.x * coord) * (_SceneFogParams.x * coord));
        }
        return saturate(fogFac);
    }

    float ComputeDistance(float3 camDir, float zdepth)
    {
        float dist = (_SceneFogMode.y == 1) ? length(camDir) : zdepth * _ProjectionParams.z;
        dist -= _ProjectionParams.y;
        return dist;
    }

    float ComputeHalfSpace(float3 wsDir)
    {
        float3 wpos = _CameraWS + wsDir;
        float FH = _HeightParams.x;
        float3 V = wsDir;
        float FdotC = _HeightParams.y;
        float k = _HeightParams.z;
        float FdotP = wpos.y - FH;
        float FdotV = wsDir.y;
        float c1 = k * (FdotP + FdotC);
        float c2 = (1 - 2 * k) * FdotP;
        float g = min(c2, 0.0);
        g = -length(_HeightParams.w * V) * (c1 - g * g / abs(FdotV + 1.0e-5f));
        return g;
    }

    half4 ComputeFog(v2f i, bool distance, bool height) : SV_Target
    {
        half4 sceneColor = tex2D(_MainTex, UnityStereoTransformScreenSpaceTex(i.uv));
        float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(i.uv_depth));
        float dpth = Linear01Depth(rawDepth);
        float4 wsDir = dpth * i.interpolatedRay;
        float4 wsPos = _CameraWS + wsDir;

        float g = _DistanceParams.x;
        if (distance)
            g += ComputeDistance(wsDir.xyz, dpth);
        if (height)
            g += ComputeHalfSpace(wsDir.xyz);

        half fogFac = ComputeFogFactor(max(0.0, g));
        if (dpth == _DistanceParams.y)
            fogFac = 1.0;

        half4 sceneColorDark = sceneColor * pow(fogFac, clamp(_EnLoss, 0.001, 100));
        return lerp(unity_FogColor * half4(_FogTint.rgb, 1), lerp(sceneColor, sceneColorDark, _MaxValue), clamp(fogFac, 1 - _MaxValue, 1));
    }

    half4 ComputeFogB(v2f i, bool distance, bool height) : SV_Target
    {
        float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(i.uv_depth));
        float dpth = Linear01Depth(rawDepth);
        float4 wsDir = dpth * i.interpolatedRay;
        float4 wsPos = _CameraWS + wsDir;

        float g = _DistanceParams.x;
        if (distance)
            g += ComputeDistance(wsDir.xyz, dpth);
        if (height)
            g += ComputeHalfSpace(wsDir.xyz);

        half fogFac = ComputeFogFactor(max(0.0, g));
        if (dpth == _DistanceParams.y)
            fogFac = 1.0;

        half fogIntensity = (unity_FogColor.r + unity_FogColor.g + unity_FogColor.b) / 3.0;
        half3 adjustedFogColor = unity_FogColor.rgb / fogIntensity;
        return half4(adjustedFogColor, 1) * (1 - fogFac);
    }

    ENDCG

    SubShader
    {
        ZTest Always Cull Off ZWrite Off Fog { Mode Off }

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            half4 frag(v2f i) : SV_Target { return ComputeFog(i, true, true); }
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            half4 frag(v2f i) : SV_Target { return ComputeFog(i, true, false); }
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            half4 frag(v2f i) : SV_Target { return ComputeFog(i, false, true); }
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            half4 frag(v2f i) : SV_Target { return ComputeFogB(i, true, true); }
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            half4 frag(v2f i) : SV_Target { return ComputeFogB(i, true, false); }
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            half4 frag(v2f i) : SV_Target { return ComputeFogB(i, false, true); }
            ENDCG
        }
    }

    Fallback off
}
